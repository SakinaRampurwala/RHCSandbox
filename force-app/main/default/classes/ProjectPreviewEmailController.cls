public without sharing class ProjectPreviewEmailController {
    
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
            'ProjectImprovementProgramPhotoRelease' => 'Project_Improvement_Program_Photo_Release'
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

        if (data == null || data.toEmails == null || data.toEmails.isEmpty()) {
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
        public String subject;
        public String htmlBody;
        public Boolean useEmailSignature;
        public Boolean saveAsActivity;
        public List<String> fileIds;
    }

}