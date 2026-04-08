public without sharing class AccountPreviewEmailController {
    
    @AuraEnabled(cacheable=true)
    public static User getEmailSignature() {
        User usr = [SELECT Id, Name, Email, Signature FROM User WHERE Id = :UserInfo.getUserId()];
        return usr;
    }

    @AuraEnabled
    public static List<OrgWideEmailAddress> getOrgWideEmailAddresses() {
        List<OrgWideEmailAddress> emailaddresList = [SELECT Id, Address, DisplayName FROM OrgWideEmailAddress WHERE IsAllowAllProfiles = true ORDER BY DisplayName ASC];
        return emailaddresList;
    }

    @AuraEnabled
    public static List<ContentVersion> getRelatedFiles(String recordId) {
        List<ContentDocumentLink> fileLinks = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :recordId];

        Set<Id> documentIds = new Set<Id>();
        for(ContentDocumentLink link : fileLinks) {
            documentIds.add(link.ContentDocumentId);
        }

        List<ContentVersion> relatedFiles = [
            SELECT Id, VersionData, ContentDocumentId, Title, ContentSize, FileType, FileExtension 
            FROM ContentVersion 
            WHERE ContentDocumentId IN :documentIds
        ];

        return relatedFiles;
    }

    @AuraEnabled
    public static Map<String, String> getEmailBody(String recordId, String vfApiName) {
        if (String.isBlank(vfApiName)) {
            return new Map<String, String>();
        }
        Map<String, String> templateMap = new Map<String, String>{
            'IneligibleHIPletter' => 'IneligibleHIPletterTemplateBody',
            'HIPEligibleLetter' => 'HIPEligibleLetterTemplateBody'
        };
        String resolvedTemplateApiName = templateMap.containsKey(vfApiName) ? templateMap.get(vfApiName) : vfApiName;

        List<EmailTemplate> templates = [
            SELECT Id, Subject, Body, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :resolvedTemplateApiName
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            return new Map<String, String>();
        }
        EmailTemplate template = templates[0];

        String body = template.HtmlValue;
        if (String.isBlank(body)) {
            body = template.Body;
        }
        String subject = template.Subject;

        if (String.isNotBlank(body) && body.contains('{!URL}')) {
            String baseUrl = getConfirmationSiteUrl();
            String safeRecordId = String.isBlank(recordId) ? '' : recordId;
            String linkText = 'Click here';
            String link = '<a href="' + baseUrl + '/apex/emailTemplateId?id=' + safeRecordId
                + '&isPreview=true&senderId=' + UserInfo.getUserId()
                + '&sendDate=' + Date.today() + '">' + linkText + '</a>';
            body = body.replace('{!URL}', link);
        }

        body = applyOrganizationMergeFields(body);

        Map<String, String> result = new Map<String, String>();
        result.put('subject', subject);
        result.put('htmlBody', body);

        return result;
    }

    private static String getConfirmationSiteUrl() {
        buildertek__ConfirmationSiteURL__c settings = buildertek__ConfirmationSiteURL__c.getOrgDefaults();
        if (settings != null && String.isNotBlank(settings.buildertek__Sites_URL__c)) {
            return settings.buildertek__Sites_URL__c;
        }
        return URL.getOrgDomainUrl().toExternalForm();
    }

    private static String applyOrganizationMergeFields(String body) {
        if (String.isBlank(body)) {
            return body;
        }

        Organization orgInfo = [SELECT Name, Street, City, State, PostalCode, Phone FROM Organization LIMIT 1];
        Map<String, String> values = new Map<String, String>{
            '{!$Organization.Name}' => safeValue(orgInfo.Name),
            '{!$Organization.Street}' => safeValue(orgInfo.Street),
            '{!$Organization.City}' => safeValue(orgInfo.City),
            '{!$Organization.State}' => safeValue(orgInfo.State),
            '{!$Organization.PostalCode}' => safeValue(orgInfo.PostalCode),
            '{!$Organization.Phone}' => safeValue(orgInfo.Phone)
        };

        for (String token : values.keySet()) {
            body = body.replace(token, values.get(token));
        }

        return body;
    }

    private static String safeValue(String value) {
        return value == null ? '' : value;
    }

    @AuraEnabled
    public static EmailResult sendEmail(String emailData) {
        DataWrap data = (DataWrap) JSON.deserialize(emailData, DataWrap.class);

        if (data == null) {
            return new EmailResult(false, 'Invalid email request');
        }

        if (data.templateId == 'FinalInspectionForm') {
            return sendFinalInspectionEmail(data);
        }

        if (data.toEmails == null || data.toEmails.isEmpty()) {
            return new EmailResult(false, 'At least one recipient is required');
        }

        List<String> toAddresses = new List<String>();
        List<String> ccAddresses = new List<String>();
        List<String> bccAddresses = new List<String>();

        toAddresses.addAll(data.toEmails);
        if (data.ccEmails != null) {
            ccAddresses.addAll(data.ccEmails);
        }
        if (data.bccEmails != null) {
            bccAddresses.addAll(data.bccEmails);
        }

        String subject = data.subject;
        if (data.includeRefId && String.isNotBlank(data.recordId)) {
            subject = subject + '[ref:' + data.recordId + ']';
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(toAddresses);
        if (!ccAddresses.isEmpty()) {
            mail.setCcAddresses(ccAddresses);
        }
        if (!bccAddresses.isEmpty()) {
            mail.setBccAddresses(bccAddresses);
        }
        if (String.isNotBlank(data.fromAddress)) {
            mail.setOrgWideEmailAddressId(data.fromAddress);
        }
        mail.setSubject(subject);
        mail.setHtmlBody(data.htmlBody);
        mail.setUseSignature(data.useEmailSignature);
        mail.setSaveAsActivity(data.saveAsActivity);
        if (isValidIdFormat(data.recordId)) {
            mail.setWhatId((Id) data.recordId);
        }

        List<Messaging.EmailFileAttachment> attachmentList = new List<Messaging.EmailFileAttachment>();
        Integer totalSize = 0;
        if (data.fileIds != null && !data.fileIds.isEmpty()) {
            List<ContentVersion> files = [
                SELECT Title, VersionData, ContentSize, FileType, FileExtension
                FROM ContentVersion
                WHERE ContentDocumentId IN :data.fileIds AND IsLatest = true
            ];

            for (ContentVersion file : files) {
                totalSize += file.ContentSize;
            }

            if (totalSize > 25 * 1024 * 1024) {
                return new EmailResult(false, 'Total attachment size exceeds 25MB limit');
            }

            for (ContentVersion file : files) {
                Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
                String extension = String.isNotBlank(file.FileExtension)
                    ? file.FileExtension
                    : (file.FileType != null ? file.FileType.toLowerCase() : '');
                attachment.setFileName(extension != '' ? file.Title + '.' + extension : file.Title);
                attachment.setBody(file.VersionData);
                attachmentList.add(attachment);
            }
        }

        if (data.templateId == 'HIPEligibleLetter' && String.isNotBlank(data.recordId)) {
            Messaging.EmailFileAttachment hipPdf = buildHipEligibleLetterAttachment(data.recordId);
            if (hipPdf != null && hipPdf.getBody() != null) {
                totalSize += hipPdf.getBody().size();
                if (totalSize > 25 * 1024 * 1024) {
                    return new EmailResult(false, 'Total attachment size exceeds 25MB limit');
                }
                attachmentList.add(hipPdf);
            }
        }

        if (data.templateId == 'IneligibleHIPletter' && String.isNotBlank(data.recordId)) {
            Messaging.EmailFileAttachment ineligibleHipPdf = buildIneligibleHipLetterAttachment(data.recordId);
            if (ineligibleHipPdf != null && ineligibleHipPdf.getBody() != null) {
                totalSize += ineligibleHipPdf.getBody().size();
                if (totalSize > 25 * 1024 * 1024) {
                    return new EmailResult(false, 'Total attachment size exceeds 25MB limit');
                }
                attachmentList.add(ineligibleHipPdf);
            }
        }

        if (!attachmentList.isEmpty()) {
            mail.setFileAttachments(attachmentList);
        }

        Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        if (!results.isEmpty() && results[0].isSuccess()) {
            return new EmailResult(true, 'Email sent successfully');
        }

        String errorMsg = 'Failed to send email';
        if (!results.isEmpty() && !results[0].getErrors().isEmpty()) {
            errorMsg = results[0].getErrors()[0].getMessage();
        }
        return new EmailResult(false, errorMsg);
    }

    private static Messaging.EmailFileAttachment buildHipEligibleLetterAttachment(String recordId) {
        if (String.isBlank(recordId)) {
            return null;
        }
        try {
            PageReference pageRef = Page.HIPEligibleLetterAsPDF;
            pageRef.getParameters().put('id', recordId);
            Blob pdfBlob = Test.isRunningTest()
                ? Blob.valueOf('HIP Eligible Letter')
                : pageRef.getContentAsPDF();
            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName('HIP Eligible Letter.pdf');
            attachment.setBody(pdfBlob);
            attachment.setContentType('application/pdf');
            return attachment;
        } catch (Exception e) {
            return null;
        }
    }

    private static Messaging.EmailFileAttachment buildIneligibleHipLetterAttachment(String recordId) {
        if (String.isBlank(recordId)) {
            return null;
        }

        try {
            PageReference pageRef;
            Blob pdfBlob;
            Messaging.EmailFileAttachment attachment;

            pageRef = Page.IneligibleHIPletterAsPDF;
            pageRef.getParameters().put('id', recordId);

            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('Ineligible HIP Letter');
            } else {
                pdfBlob = pageRef.getContentAsPDF();
            }

            attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName('Ineligible HIP Letter.pdf');
            attachment.setBody(pdfBlob);
            attachment.setContentType('application/pdf');

            return attachment;
        } catch (Exception e) {
            return null;
        }
    }

    private static EmailResult sendFinalInspectionEmail(DataWrap data) {
        if (String.isBlank(data.recordId)) {
            return new EmailResult(false, 'Record Id is required');
        }

        if (isFinalInspectionAlreadySubmitted((Id) data.recordId)) {
            return new EmailResult(false, 'Final Inspection already completed');
        }

        FinalInspectionSignatureState sigState = getFinalInspectionSignatureState((Id) data.recordId);
        Boolean needsVendor = !sigState.homeownerSigned;
        Boolean needsCompany = sigState.homeownerSigned && !sigState.representativeSigned;

        if (!needsVendor && !needsCompany) {
            return new EmailResult(false, 'Final Inspection already completed');
        }

        List<Contact> recipients = new List<Contact>();
        Boolean isVendor = false;
        Boolean isCompany = false;

        if (needsVendor) {
            if (data.vendorContactIds == null || data.vendorContactIds.isEmpty()) {
                return new EmailResult(false, 'At least one homeowner recipient is required');
            }
            recipients = [
                SELECT Id, Name, Email
                FROM Contact
                WHERE Id IN :data.vendorContactIds
            ];
            if (recipients.isEmpty()) {
                return new EmailResult(false, 'No valid homeowner recipients found');
            }
            isVendor = true;
        } else if (needsCompany) {
            if (data.companyContactIds == null || data.companyContactIds.isEmpty()) {
                return new EmailResult(false, 'At least one program representative contact is required');
            }
            recipients = [
                SELECT Id, Name, Email
                FROM Contact
                WHERE Id IN :data.companyContactIds
            ];
            if (recipients.isEmpty()) {
                return new EmailResult(false, 'No valid program representative recipients found');
            }
            isCompany = true;
        }

        String subject = data.subject;
        if (data.includeRefId && String.isNotBlank(data.recordId)) {
            subject = subject + '[ref:' + data.recordId + ']';
        }

        List<Messaging.EmailFileAttachment> attachmentList = new List<Messaging.EmailFileAttachment>();
        if (data.fileIds != null && !data.fileIds.isEmpty()) {
            List<ContentVersion> files = [
                SELECT Title, VersionData, ContentSize, FileType, FileExtension
                FROM ContentVersion
                WHERE ContentDocumentId IN :data.fileIds AND IsLatest = true
            ];

            Integer totalSize = 0;
            for (ContentVersion file : files) {
                totalSize += file.ContentSize;
            }

            if (totalSize > 25 * 1024 * 1024) {
                return new EmailResult(false, 'Total attachment size exceeds 25MB limit');
            }

            for (ContentVersion file : files) {
                Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
                String extension = String.isNotBlank(file.FileExtension)
                    ? file.FileExtension
                    : (file.FileType != null ? file.FileType.toLowerCase() : '');
                attachment.setFileName(extension != '' ? file.Title + '.' + extension : file.Title);
                attachment.setBody(file.VersionData);
                attachmentList.add(attachment);
            }
        }

        String baseBody = data.htmlBody == null ? '' : data.htmlBody;
        String roleBody = applyFinalInspectionParamsToBody(
            baseBody,
            data.templateId,
            data.recordId,
            isVendor,
            isCompany,
            data.companyContactIds,
            data.companyEmails,
            data.fromAddress,
            data.fileIds
        );

        List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
        List<Messaging.SendEmailResult> results = new List<Messaging.SendEmailResult>();

        for (Contact recipient : recipients) {
            if (recipient == null || String.isBlank(recipient.Email)) {
                continue;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ recipient.Email });
            if (String.isNotBlank(data.fromAddress)) {
                mail.setOrgWideEmailAddressId(data.fromAddress);
            }
            mail.setSubject(subject);
            mail.setHtmlBody(applyContactName(roleBody, recipient.Name, data.contactNameToken, data.lastSelectedContactName));
            mail.setUseSignature(data.useEmailSignature);
            mail.setSaveAsActivity(data.saveAsActivity);
            if (isValidIdFormat(data.recordId)) {
                mail.setWhatId((Id) data.recordId);
            }
            if (!attachmentList.isEmpty()) {
                mail.setFileAttachments(attachmentList);
            }

            batch.add(mail);
            if (batch.size() == 10) {
                results.addAll(Messaging.sendEmail(batch));
                batch.clear();
            }
        }

        if (!batch.isEmpty()) {
            results.addAll(Messaging.sendEmail(batch));
        }

        if (results.isEmpty()) {
            return new EmailResult(false, 'No valid recipients found');
        }

        for (Messaging.SendEmailResult result : results) {
            if (!result.isSuccess()) {
                if (result.getErrors() != null && !result.getErrors().isEmpty()) {
                    return new EmailResult(false, result.getErrors()[0].getMessage());
                }
                return new EmailResult(false, 'Failed to send email');
            }
        }

        return new EmailResult(true, 'Email sent successfully');
    }

    private class FinalInspectionSignatureState {
        public Boolean homeownerSigned { get; set; }
        public Boolean representativeSigned { get; set; }

        public FinalInspectionSignatureState(Boolean homeownerSigned, Boolean representativeSigned) {
            this.homeownerSigned = homeownerSigned;
            this.representativeSigned = representativeSigned;
        }
    }

    private static FinalInspectionSignatureState getFinalInspectionSignatureState(Id recordId) {
        if (recordId == null) {
            return new FinalInspectionSignatureState(false, false);
        }

        Map<String, Schema.SObjectField> fieldMap = buildertek__Project__c.SObjectType.getDescribe().fields.getMap();
        List<String> queryFields = new List<String>{ 'Id' };
        if (fieldMap.containsKey('FI_Homeowner_Sign_Id__c')) {
            queryFields.add('FI_Homeowner_Sign_Id__c');
        }
        if (fieldMap.containsKey('FI_Representative_Sign_Id__c')) {
            queryFields.add('FI_Representative_Sign_Id__c');
        }

        if (queryFields.size() == 1) {
            return new FinalInspectionSignatureState(false, false);
        }

        SObject recordSObj = Database.query(
            'SELECT ' + String.join(queryFields, ',') + ' FROM buildertek__Project__c WHERE Id = :recordId LIMIT 1'
        );

        String homeownerSignId = fieldMap.containsKey('FI_Homeowner_Sign_Id__c')
            ? (String) recordSObj.get('FI_Homeowner_Sign_Id__c')
            : null;
        String representativeSignId = fieldMap.containsKey('FI_Representative_Sign_Id__c')
            ? (String) recordSObj.get('FI_Representative_Sign_Id__c')
            : null;

        Boolean homeownerSigned = String.isNotBlank(homeownerSignId);
        Boolean representativeSigned = String.isNotBlank(representativeSignId);

        return new FinalInspectionSignatureState(homeownerSigned, representativeSigned);
    }

    private static Boolean isFinalInspectionAlreadySubmitted(Id recordId) {
        if (recordId == null) {
            return false;
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Title, ContentDocument.FileType
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
        ];

        for (ContentDocumentLink link : links) {
            if (link.ContentDocument != null
                && link.ContentDocument.FileType == 'PDF'
                && link.ContentDocument.Title != null
                && link.ContentDocument.Title.startsWith('Final Inspection ')) {
                return true;
            }
        }

        return false;
    }

    private static String applyFinalInspectionParamsToBody(
        String body,
        String templateId,
        String recordId,
        Boolean isVendor,
        Boolean isCompany,
        List<String> companyContactIds,
        List<String> companyEmails,
        String fromAddressId,
        List<String> fileIds
    ) {
        if (String.isBlank(body)) {
            return body;
        }

        Pattern pattern = Pattern.compile('(?i)href="([^"]+)"');
        Matcher matcher = pattern.matcher(body);
        List<String> parts = new List<String>();
        String token = String.isBlank(templateId) ? null : '/apex/' + templateId;
        Integer lastIndex = 0;

        while (matcher.find()) {
            parts.add(body.substring(lastIndex, matcher.start()));

            String url = matcher.group(1);
            String updatedUrl = url;
            if (String.isNotBlank(url) && (token == null || url.contains(token))) {
                updatedUrl = addOrReplaceUrlParam(updatedUrl, 'recordId', recordId);
                updatedUrl = addOrReplaceUrlParam(updatedUrl, 'isPreview', 'false');
                updatedUrl = addOrReplaceUrlParam(updatedUrl, 'isVendor', String.valueOf(isVendor));
                updatedUrl = addOrReplaceUrlParam(updatedUrl, 'isCompany', String.valueOf(isCompany));
                String companyIdsValue = joinIds(companyContactIds);
                if (String.isNotBlank(companyIdsValue)) {
                    updatedUrl = addOrReplaceUrlParam(updatedUrl, 'companyContactIds', companyIdsValue);
                }
                String companyEmailsValue = joinIds(companyEmails);
                if (String.isNotBlank(companyEmailsValue)) {
                    updatedUrl = addOrReplaceUrlParam(updatedUrl, 'companyEmails', companyEmailsValue);
                }
                if (String.isNotBlank(fromAddressId)) {
                    updatedUrl = addOrReplaceUrlParam(updatedUrl, 'fromAddressId', fromAddressId);
                }
                String fileIdsValue = joinIds(fileIds);
                if (String.isNotBlank(fileIdsValue)) {
                    updatedUrl = addOrReplaceUrlParam(updatedUrl, 'fileIds', fileIdsValue);
                }
            }

            parts.add('href="' + updatedUrl + '"');
            lastIndex = matcher.end();
        }

        parts.add(body.substring(lastIndex));
        return String.join(parts, '');
    }

    private static String addOrReplaceUrlParam(String url, String key, String value) {
        if (String.isBlank(url) || String.isBlank(key)) {
            return url;
        }
        String encodedKey = EncodingUtil.urlEncode(key, 'UTF-8');
        String encodedValue = value == null ? '' : EncodingUtil.urlEncode(value, 'UTF-8');
        Pattern pattern = Pattern.compile('([?&])' + encodedKey + '=[^&]*');
        Matcher matcher = pattern.matcher(url);
        if (matcher.find()) {
            return matcher.replaceAll('$1' + encodedKey + '=' + encodedValue);
        }
        String separator = url.contains('?') ? '&' : '?';
        return url + separator + encodedKey + '=' + encodedValue;
    }

    private static String joinIds(List<String> ids) {
        if (ids == null || ids.isEmpty()) {
            return '';
        }
        List<String> cleaned = new List<String>();
        for (String idVal : ids) {
            if (String.isNotBlank(idVal)) {
                cleaned.add(idVal);
            }
        }
        return cleaned.isEmpty() ? '' : String.join(cleaned, ',');
    }

    private static String applyContactName(String body, String contactName, String token, String lastSelectedName) {
        if (String.isBlank(body) || String.isBlank(contactName)) {
            return body;
        }

        String updatedBody = body;
        if (String.isNotBlank(token) && updatedBody.contains(token)) {
            updatedBody = updatedBody.replace(token, contactName);
        } else if (String.isNotBlank(lastSelectedName) && updatedBody.contains(lastSelectedName)) {
            updatedBody = updatedBody.replace(lastSelectedName, contactName);
        } else if (updatedBody.contains('{!ContactName}')) {
            updatedBody = updatedBody.replace('{!ContactName}', contactName);
        }

        return updatedBody;
    }

    @AuraEnabled
    public static Map<String, String> saveSignature(String recordId, String signatureBase64Data) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(signatureBase64Data)) {
            return result;
        }

        ContentVersion conVer = new ContentVersion();
        conVer.ContentLocation = 'S';
        conVer.PathOnClient = 'PathStoneSignature.png';
        conVer.Title = 'PathStone Signature';
        conVer.VersionData = EncodingUtil.base64Decode(signatureBase64Data);
        conVer.IsMajorVersion = true;
        insert conVer;

        Id conDocId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :conVer.Id
        ].ContentDocumentId;

        Id safeRecordId = isValidIdFormat(recordId) ? (Id) recordId : null;
        if (safeRecordId != null) {
            ContentDocumentLink conDocLink = new ContentDocumentLink();
            conDocLink.LinkedEntityId = safeRecordId;
            conDocLink.ContentDocumentId = conDocId;
            conDocLink.ShareType = 'I';
            insert conDocLink;
        }

        ContentDistribution cd = new ContentDistribution();
        cd.Name = 'PathStone Signature';
        cd.ContentVersionId = conVer.Id;
        cd.PreferencesAllowViewInBrowser = true;
        cd.PreferencesNotifyOnVisit = false;
        Database.SaveResult cdResult = Database.insert(cd, false);
        if (cdResult.isSuccess()) {
            cd = [SELECT ContentDownloadUrl FROM ContentDistribution WHERE Id = :cdResult.getId()];
            if (String.isNotBlank(cd.ContentDownloadUrl)) {
                result.put('imgUrl', cd.ContentDownloadUrl);
            }
        }

        result.put('cvId', conVer.Id);
        return result;
    }

    private static Boolean isValidIdFormat(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        Boolean isValid = Pattern.matches('^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$', value);
        return isValid;
    }

    public class EmailResult {
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String errorMessage;
        public EmailResult(Boolean isSuccess, String errorMessage) {
            this.isSuccess = isSuccess;
            this.errorMessage = errorMessage;
        }
    }

    public class DataWrap {
        public String recordId;
        public Boolean includeRefId;
        public String templateId;
        public String fromAddress;
        public List<String> toContactIds;
        public List<String> toEmails;
        public List<String> ccEmails;
        public List<String> bccEmails;
        public List<String> vendorContactIds;
        public List<String> vendorEmails;
        public List<String> companyContactIds;
        public List<String> companyEmails;
        public String subject;
        public String htmlBody;
        public String contactNameToken;
        public String lastSelectedContactName;
        public Boolean useEmailSignature;
        public Boolean saveAsActivity;
        public List<String> fileIds;
    }

}