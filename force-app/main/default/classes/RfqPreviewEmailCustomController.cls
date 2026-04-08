public without sharing class RfqPreviewEmailCustomController {

    private static final String CONTRACTOR_SELECTED_TEMPLATE_KEY = 'ContractorSelectedForm';
    private static final String CONTRACTOR_SELECTED_TEMPLATE_NAME = 'ContractorSelectedFormTemplateBody';
    private static final String CONTRACTOR_SELECTED_PAGE_NAME = 'ContractorSelectedForm';

    @AuraEnabled(cacheable=true)
    public static User getEmailSignature() {
        return [
            SELECT Id, Name, Email, Signature
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
    }

    @AuraEnabled
    public static List<OrgWideEmailAddress> getOrgWideEmailAddresses() {
        return [
            SELECT Id, Address, DisplayName
            FROM OrgWideEmailAddress
            WHERE IsAllowAllProfiles = true
            ORDER BY DisplayName ASC
        ];
    }

    @AuraEnabled
    public static Map<String, String> getEmailBody(String recordId, String vfApiName) {
        if (String.isBlank(vfApiName)) {
            return new Map<String, String>();
        }

        String developerName = resolveTemplateDeveloperName(vfApiName);
        if (String.isBlank(developerName)) {
            return new Map<String, String>();
        }

        List<EmailTemplate> templateList = [
            SELECT Id, Subject, Body, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];

        if (templateList.isEmpty()) {
            return new Map<String, String>();
        }

        EmailTemplate templateRecord = templateList[0];
        String emailBody = String.isNotBlank(templateRecord.HtmlValue)
            ? templateRecord.HtmlValue
            : templateRecord.Body;

        emailBody = applyTemplateLink(emailBody, recordId, vfApiName, true);
        emailBody = applyOrganizationMergeFields(emailBody);

        Map<String, String> response = new Map<String, String>();
        response.put('subject', templateRecord.Subject);
        response.put('htmlBody', emailBody);
        return response;
    }

    @AuraEnabled
    public static EmailResult sendEmail(String emailData) {
        if (String.isBlank(emailData)) {
            return new EmailResult(false, 'Invalid email request');
        }

        DataWrap data = (DataWrap) JSON.deserialize(emailData, DataWrap.class);
        if (data == null) {
            return new EmailResult(false, 'Invalid email request');
        }

        List<String> validationErrors = validateEmailRequest(data);
        if (!validationErrors.isEmpty()) {
            return new EmailResult(false, String.join(validationErrors, ' '));
        }

        Savepoint launchSavepoint = Database.setSavepoint();

        try {
            persistLauncherSnapshot(data);

            Messaging.SingleEmailMessage emailMessage = new Messaging.SingleEmailMessage();
            emailMessage.setToAddresses(data.toEmails);

            if (data.ccEmails != null && !data.ccEmails.isEmpty()) {
                emailMessage.setCcAddresses(data.ccEmails);
            }

            if (data.bccEmails != null && !data.bccEmails.isEmpty()) {
                emailMessage.setBccAddresses(data.bccEmails);
            }

            if (String.isNotBlank(data.fromAddress)) {
                emailMessage.setOrgWideEmailAddressId(data.fromAddress);
            }

            String subjectLine = data.subject;
            if (data.includeRefId == true && String.isNotBlank(data.recordId)) {
                subjectLine += ' [ref:' + data.recordId + ']';
            }

            emailMessage.setSubject(subjectLine);
            emailMessage.setHtmlBody(data.htmlBody);
            emailMessage.setUseSignature(data.useEmailSignature == true);
            emailMessage.setSaveAsActivity(data.saveAsActivity == true);

            if (isValidIdFormat(data.recordId)) {
                emailMessage.setWhatId((Id) data.recordId);
            }

            Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(
                new Messaging.SingleEmailMessage[] { emailMessage }
            );

            if (!sendResults.isEmpty() && sendResults[0].isSuccess()) {
                return new EmailResult(true, 'Email sent successfully');
            }

            Database.rollback(launchSavepoint);

            String errorMessage = 'Failed to send email';
            if (!sendResults.isEmpty() && sendResults[0].getErrors() != null && !sendResults[0].getErrors().isEmpty()) {
                errorMessage = sendResults[0].getErrors()[0].getMessage();
            }

            return new EmailResult(false, errorMessage);
        } catch (Exception ex) {
            Database.rollback(launchSavepoint);
            return new EmailResult(false, ex.getMessage());
        }
    }

    private static List<String> validateEmailRequest(DataWrap data) {
        List<String> errors = new List<String>();
        String representativeContactId = resolveProgramRepresentativeContactId(data);
        String representativeEmail = resolveProgramRepresentativeEmail(data);

        if (data.toEmails == null || data.toEmails.isEmpty()) {
            errors.add('At least one homeowner recipient is required.');
        }

        if (String.isBlank(data.subject)) {
            errors.add('Email subject is required.');
        }

        if (String.isBlank(stripHtml(data.htmlBody))) {
            errors.add('Email body is required.');
        }

        if (String.isBlank(data.templateId)) {
            errors.add('A template selection is required.');
        }

        if (String.isBlank(representativeContactId) || !isValidIdFormat(representativeContactId)) {
            errors.add('A Program Representative contact is required.');
        }

        if (String.isBlank(representativeEmail)) {
            errors.add('A Program Representative email snapshot is required.');
        }

        if (String.isBlank(data.recordId) || !isValidIdFormat(data.recordId)) {
            errors.add('A valid RFQ record id is required.');
        }

        return errors;
    }

    private static void persistLauncherSnapshot(DataWrap data) {
        if (!isValidIdFormat(data.recordId)) {
            return;
        }

        String representativeEmail = resolveProgramRepresentativeEmail(data);
        buildertek__RFQ__c rfqUpdate = new buildertek__RFQ__c(
            Id = (Id) data.recordId
        );
        rfqUpdate.Contractor_Selected_Program_Staff_User__c = null;
        rfqUpdate.Contractor_Selected_Program_Staff_Email__c = representativeEmail;
        rfqUpdate.Contractor_Selected_Homeowner_Req_Sent__c = System.now();
        update rfqUpdate;
    }

    private static String resolveProgramRepresentativeContactId(DataWrap data) {
        if (data == null) {
            return null;
        }

        if (String.isNotBlank(data.programRepresentativeContactId)) {
            return data.programRepresentativeContactId;
        }

        return data.programStaffUserId;
    }

    private static String resolveProgramRepresentativeEmail(DataWrap data) {
        if (data == null) {
            return null;
        }

        if (String.isNotBlank(data.programRepresentativeEmail)) {
            return data.programRepresentativeEmail;
        }

        return data.programStaffEmail;
    }

    private static String resolveTemplateDeveloperName(String templateKey) {
        if (templateKey == CONTRACTOR_SELECTED_TEMPLATE_KEY || templateKey == CONTRACTOR_SELECTED_TEMPLATE_NAME) {
            return CONTRACTOR_SELECTED_TEMPLATE_NAME;
        }

        return null;
    }

    private static String applyTemplateLink(String emailBody, String recordId, String templateKey, Boolean isPreview) {
        if (String.isBlank(emailBody) || !emailBody.contains('{!URL}')) {
            return emailBody;
        }

        String linkTarget = buildPageUrl(recordId, templateKey, isPreview);
        String linkMarkup = '<a href="' + linkTarget + '">Open Contractor Selected Form</a>';
        return emailBody.replace('{!URL}', linkMarkup);
    }

    private static String buildPageUrl(String recordId, String templateKey, Boolean isPreview) {
        String pageName = resolveTemplatePageName(templateKey);
        String baseUrl = getConfirmationSiteUrl();
        String safeRecordId = String.isBlank(recordId) ? '' : EncodingUtil.urlEncode(recordId, 'UTF-8');
        String safeSenderId = EncodingUtil.urlEncode(UserInfo.getUserId(), 'UTF-8');
        String safeSendDate = EncodingUtil.urlEncode(String.valueOf(Date.today()), 'UTF-8');
        String previewValue = isPreview == true ? 'true' : 'false';

        return baseUrl + '/apex/' + pageName
            + '?recordId=' + safeRecordId
            + '&isPreview=' + previewValue
            + '&senderId=' + safeSenderId
            + '&sendDate=' + safeSendDate;
    }

    private static String resolveTemplatePageName(String templateKey) {
        if (templateKey == CONTRACTOR_SELECTED_TEMPLATE_KEY || templateKey == CONTRACTOR_SELECTED_TEMPLATE_NAME) {
            return CONTRACTOR_SELECTED_PAGE_NAME;
        }

        return CONTRACTOR_SELECTED_PAGE_NAME;
    }

    private static String getConfirmationSiteUrl() {
        buildertek__ConfirmationSiteURL__c settings = buildertek__ConfirmationSiteURL__c.getOrgDefaults();
        if (settings != null && String.isNotBlank(settings.buildertek__Sites_URL__c)) {
            return normalizeBaseUrl(settings.buildertek__Sites_URL__c);
        }

        return normalizeBaseUrl(URL.getOrgDomainUrl().toExternalForm());
    }

    private static String normalizeBaseUrl(String baseUrl) {
        if (String.isBlank(baseUrl)) {
            return '';
        }

        String normalizedUrl = baseUrl.trim();
        while (normalizedUrl.endsWith('/')) {
            normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length() - 1);
        }

        return normalizedUrl;
    }

    private static String applyOrganizationMergeFields(String emailBody) {
        if (String.isBlank(emailBody)) {
            return emailBody;
        }

        Organization organizationInfo = [
            SELECT Name, Street, City, State, PostalCode, Phone
            FROM Organization
            LIMIT 1
        ];

        Map<String, String> mergeValues = new Map<String, String>{
            '{!$Organization.Name}' => safeValue(organizationInfo.Name),
            '{!$Organization.Street}' => safeValue(organizationInfo.Street),
            '{!$Organization.City}' => safeValue(organizationInfo.City),
            '{!$Organization.State}' => safeValue(organizationInfo.State),
            '{!$Organization.PostalCode}' => safeValue(organizationInfo.PostalCode),
            '{!$Organization.Phone}' => safeValue(organizationInfo.Phone)
        };

        for (String token : mergeValues.keySet()) {
            emailBody = emailBody.replace(token, mergeValues.get(token));
        }

        return emailBody;
    }

    private static String safeValue(String value) {
        return value == null ? '' : value;
    }

    private static String stripHtml(String value) {
        if (String.isBlank(value)) {
            return '';
        }

        return value.replaceAll('<[^>]+>', ' ').trim();
    }

    private static Boolean isValidIdFormat(String value) {
        if (String.isBlank(value)) {
            return false;
        }

        return Pattern.matches('^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$', value);
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
        public String programRepresentativeContactId;
        public String programRepresentativeName;
        public String programRepresentativeEmail;
        public String programStaffUserId;
        public String programStaffEmail;
    }
}