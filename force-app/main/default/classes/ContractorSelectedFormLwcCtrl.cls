public without sharing class ContractorSelectedFormLwcCtrl {

    private static final String HOMEOWNER_SIGNATURE_LABEL = 'Homeowner';
    private static final String PROGRAM_STAFF_SIGNATURE_LABEL = 'Program Staff';
    private static final String PROGRAM_STAFF_TEMPLATE_NAME = 'ContractorSelectedFormProgramStaffTemplateBody';
    private static final String PROGRAM_STAFF_TEMPLATE_FALLBACK_SUBJECT =
        'Contractor Selected Form - Program Representative Countersign Required';

    public String vfRecordId { get; set; }
    public String vfSenderId { get; set; }
    public String vfSendDate { get; set; }
    public String vfProgramStaffInitials { get; set; }
    public String logoUrl { get; set; }
    public String displayDate { get; set; }
    public String propertyAddress { get; set; }
    public String cityTown { get; set; }
    public String zipCode { get; set; }
    public String ownerNames { get; set; }
    public String ownerPhone { get; set; }
    public String ownerEmail { get; set; }
    public String ownerNotes { get; set; }
    public String homeownerSignatureUrl { get; set; }
    public String programStaffSignatureUrl { get; set; }
    public List<PdfVendorRow> pdfVendorRows { get; set; }

    public class FormContext {
        @AuraEnabled public String propertyAddress;
        @AuraEnabled public String cityTown;
        @AuraEnabled public String zipCode;
        @AuraEnabled public String ownerNames;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
    }

    public class ContractorSelectedFormState {
        @AuraEnabled public Boolean isSubmitted;
        @AuraEnabled public Boolean isGuestUser;
        @AuraEnabled public Boolean canFinalize;
        @AuraEnabled public String stage;
        @AuraEnabled public String selectedVendorId;
        @AuraEnabled public String homeownerInitials;
        @AuraEnabled public String homeownerNotes;
        @AuraEnabled public String programStaffInitials;
        @AuraEnabled public String homeownerSignatureId;
        @AuraEnabled public String homeownerSignatureUrl;
        @AuraEnabled public String programStaffSignatureId;
        @AuraEnabled public String programStaffSignatureUrl;
        @AuraEnabled public String programStaffUserId;
        @AuraEnabled public String programStaffName;
        @AuraEnabled public String programStaffEmail;
        @AuraEnabled public String submittedDate;
        @AuraEnabled public String infoMessage;
    }

    public class PdfVendorRow {
        public String id { get; set; }
        public String contractorName { get; set; }
        public String bidAmount { get; set; }
        public String bidLabel { get; set; }
        public String selectionMark { get; set; }
        public String homeownerInitials { get; set; }
        public String programStaffInitials { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static String getLogoUrl() {
        buildertek__ConfirmationSiteURL__c sitesUrl = buildertek__ConfirmationSiteURL__c.getOrgDefaults();
        String baseUrl = '';

        if (sitesUrl != null && !String.isBlank(sitesUrl.buildertek__Sites_URL__c)) {
            baseUrl = normalizeBaseUrl(sitesUrl.buildertek__Sites_URL__c);
        } else {
            baseUrl = normalizeBaseUrl(URL.getOrgDomainUrl().toExternalForm());
        }

        List<Document> logoDocs = [SELECT Id FROM Document WHERE DeveloperName = 'Company_Logo' LIMIT 1];
        if (logoDocs.isEmpty()) {
            logoDocs = [SELECT Id FROM Document WHERE Name = 'BuildettekLogo' LIMIT 1];
        }

        if (logoDocs.isEmpty()) {
            return null;
        }

        return baseUrl + '/servlet/servlet.FileDownload?file=' + logoDocs[0].Id;
    }

    @AuraEnabled(cacheable=true)
    public static FormContext getFormContext(Id recordId) {
        return getFormContextInternal(recordId);
    }

    @AuraEnabled
    public static ContractorSelectedFormState getContractorSelectedFormState(
        Id recordId,
        Boolean allowRepresentativeAccess,
        String programRepresentativeName
    ) {
        ContractorSelectedFormState state = new ContractorSelectedFormState();
        state.stage = 'HOMEOWNER';
        state.isSubmitted = false;
        state.isGuestUser = isGuestUser();
        state.canFinalize = false;

        if (recordId == null) {
            return state;
        }

        buildertek__RFQ__c rfq = getRfqStageRecord(recordId);
        if (rfq == null) {
            return state;
        }

        state.isSubmitted = rfq.Contractor_Selected_Form_Submitted__c;
        state.selectedVendorId = rfq.Contractor_Selected_RFQ_To_Vendor__c != null
            ? String.valueOf(rfq.Contractor_Selected_RFQ_To_Vendor__c)
            : '';
        state.homeownerInitials = rfq.Contractor_Selected_HomeOwner_Initials__c;
        state.homeownerNotes = rfq.Contractor_Selected_Homeowner_Notes__c;
        state.programStaffInitials = rfq.Contractor_Selected_Prgm_Staff_Initials__c;
        state.homeownerSignatureId = rfq.Contractor_Selected_HomeOwner_SignID__c;
        state.programStaffSignatureId = rfq.Contractor_Selected_Prog_Staff_Sign_ID__c;
        state.programStaffUserId = (String) rfq.Contractor_Selected_Program_Staff_User__c;
        state.programStaffName = String.isNotBlank(programRepresentativeName)
            ? programRepresentativeName
            : (rfq.Contractor_Selected_Program_Staff_User__r != null
                ? rfq.Contractor_Selected_Program_Staff_User__r.Name
                : '');
        state.programStaffEmail = String.isNotBlank(rfq.Contractor_Selected_Program_Staff_Email__c)
            ? rfq.Contractor_Selected_Program_Staff_Email__c
            : (rfq.Contractor_Selected_Program_Staff_User__r != null
                ? rfq.Contractor_Selected_Program_Staff_User__r.Email
                : '');
        state.submittedDate = rfq.Contractor_Selected_Form_Submitted_Date__c != null
            ? formatShortDate(rfq.Contractor_Selected_Form_Submitted_Date__c)
            : '';
        state.homeownerSignatureUrl = resolveSignatureUrl(rfq.Contractor_Selected_HomeOwner_SignID__c);
        state.programStaffSignatureUrl = resolveSignatureUrl(rfq.Contractor_Selected_Prog_Staff_Sign_ID__c);

        Boolean homeownerStageComplete = isHomeownerStageComplete(rfq);
        Boolean programStaffAuthorized = isProgramStaffAuthorized(rfq, allowRepresentativeAccess);
        state.canFinalize = homeownerStageComplete && programStaffAuthorized && !state.isSubmitted;

        if (state.isSubmitted) {
            state.stage = 'COMPLETED';
            state.infoMessage = 'Contractor Selected Form Completed';
            return state;
        }

        if (!homeownerStageComplete) {
            state.stage = 'HOMEOWNER';
            return state;
        }

        if (programStaffAuthorized) {
            state.stage = 'PROGRAM_STAFF';
            state.infoMessage = 'Stage 1 is complete. Review the homeowner selection and finalize the form.';
            return state;
        }

        if (state.isGuestUser) {
            state.stage = 'HOMEOWNER_COMPLETE';
            state.infoMessage = 'Your Contractor Selected Form has been submitted. The Program Representative has been notified.';
            return state;
        }

        state.stage = 'LOCKED';
        state.infoMessage = String.isNotBlank(state.programStaffName)
            ? 'This form is awaiting countersignature by ' + state.programStaffName + '.'
            : 'This form is awaiting Program Representative countersignature.';
        return state;
    }

    @AuraEnabled(cacheable=true)
    public static List<buildertek__RFQ_To_Vendor__c> getRfqToVendors(Id recordId) {
        if (recordId == null) {
            return new List<buildertek__RFQ_To_Vendor__c>();
        }

        return [
            SELECT Id,
                   Name,
                   buildertek__Vendor__r.Name,
                   buildertek__Vendor_Quote_Amount__c
            FROM buildertek__RFQ_To_Vendor__c
            WHERE buildertek__RFQ__c = :recordId
            ORDER BY CreatedDate
        ];
    }

    @AuraEnabled
    public static Map<String, String> saveSignature(
        Id recordId,
        String signatureBody,
        String signatureLabel,
        Boolean allowRepresentativeAccess
    ) {
        if (recordId == null) {
            throw new AuraHandledException('A valid RFQ record id is required.');
        }

        if (String.isBlank(signatureBody)) {
            throw new AuraHandledException('Signature data is missing.');
        }

        String normalizedLabel = normalizeSignatureLabel(signatureLabel);
        if (normalizedLabel == PROGRAM_STAFF_SIGNATURE_LABEL) {
            buildertek__RFQ__c rfq = getRfqStageRecord(recordId);
            if (!isProgramStaffAuthorized(rfq, allowRepresentativeAccess)) {
                throw new AuraHandledException('Only someone with the Program Representative link can submit this signature.');
            }
        }

        ContentVersion versionRecord = new ContentVersion();
        versionRecord.Title = 'Contractor Selected Form ' + normalizedLabel + ' Signature';
        versionRecord.PathOnClient = 'ContractorSelectedForm'
            + normalizedLabel.replaceAll('[^A-Za-z0-9]+', '')
            + 'Signature.png';
        versionRecord.VersionData = EncodingUtil.base64Decode(signatureBody);
        versionRecord.IsMajorVersion = true;
        insert versionRecord;

        updateSignatureFields(recordId, normalizedLabel, versionRecord.Id);
        linkContentToRfq(recordId, versionRecord.Id);

        ContentDistribution distributionRecord = new ContentDistribution();
        distributionRecord.Name = 'Contractor Selected Form ' + normalizedLabel + ' Signature';
        distributionRecord.ContentVersionId = versionRecord.Id;
        distributionRecord.PreferencesAllowViewInBrowser = true;
        distributionRecord.PreferencesNotifyOnVisit = false;
        Database.SaveResult distributionResult = Database.insert(distributionRecord, false);

        String fallbackUrl = buildVersionDownloadUrl(versionRecord.Id);
        String finalUrl = fallbackUrl;

        if (distributionResult.isSuccess()) {
            ContentDistribution savedDistribution = [
                SELECT ContentDownloadUrl
                FROM ContentDistribution
                WHERE Id = :distributionResult.getId()
                LIMIT 1
            ];
            if (String.isNotBlank(savedDistribution.ContentDownloadUrl)) {
                finalUrl = savedDistribution.ContentDownloadUrl;
            }
        }

        Map<String, String> result = new Map<String, String>();
        result.put('imgUrl', finalUrl);
        result.put('cvId', versionRecord.Id);
        return result;
    }

    @AuraEnabled
    public static String submitHomeownerStage(
        Id recordId,
        Id selectedVendorId,
        String homeownerInitials,
        String homeownerNotes,
        String senderId,
        String sendDate,
        String fromAddressId,
        String programRepresentativeName
    ) {
        if (recordId == null) {
            throw new AuraHandledException('A valid RFQ record id is required.');
        }

        buildertek__RFQ__c rfq = getRfqStageRecord(recordId);
        validateHomeownerStageInput(rfq, recordId, selectedVendorId, homeownerInitials);

        Savepoint homeownerSavepoint = Database.setSavepoint();
        try {
            String normalizedHomeownerInitials = String.isBlank(homeownerInitials)
                ? null
                : homeownerInitials.trim();
            buildertek__RFQ__c rfqUpdate = new buildertek__RFQ__c(Id = recordId);
            rfqUpdate.Contractor_Selected_RFQ_To_Vendor__c = selectedVendorId;
            rfqUpdate.Contractor_Selected_HomeOwner_Initials__c = normalizedHomeownerInitials;
            rfqUpdate.Contractor_Selected_Homeowner_Notes__c = String.isBlank(homeownerNotes)
                ? null
                : homeownerNotes.trim();
            rfqUpdate.Contractor_Selected_Prog_Staff_Req_Sent__c = System.now();
            update rfqUpdate;

            String sendResult = sendProgramStaffStageEmail(
                rfq,
                senderId,
                sendDate,
                fromAddressId,
                programRepresentativeName
            );
            if (sendResult != 'Success') {
                throw new AuraHandledException(sendResult);
            }

            return 'Success';
        } catch (Exception ex) {
            Database.rollback(homeownerSavepoint);
            if (ex instanceof AuraHandledException) {
                throw ex;
            }
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static String finalizeProgramStaffStage(
        Id recordId,
        String programStaffInitials,
        String senderId,
        String sendDate,
        Boolean allowRepresentativeAccess
    ) {
        if (recordId == null) {
            throw new AuraHandledException('A valid RFQ record id is required.');
        }

        buildertek__RFQ__c rfq = getRfqStageRecord(recordId);
        if (rfq == null) {
            throw new AuraHandledException('The RFQ could not be found.');
        }

        if (rfq.Contractor_Selected_Form_Submitted__c) {
            return 'Already Submitted';
        }

        if (!isProgramStaffAuthorized(rfq, allowRepresentativeAccess)) {
            throw new AuraHandledException('Only someone with the Program Representative link can finalize this form.');
        }

        if (!isHomeownerStageComplete(rfq)) {
            throw new AuraHandledException('The homeowner stage must be completed before finalization.');
        }

        if (String.isBlank(rfq.Contractor_Selected_Prog_Staff_Sign_ID__c)) {
            throw new AuraHandledException('Program Representative signature is required.');
        }

        String normalizedProgramStaffInitials = String.isBlank(programStaffInitials)
            ? null
            : programStaffInitials.trim();
        PageReference pdfPage = Page.ContractorSelectedFormAsPDF;
        pdfPage.getParameters().put('recordId', String.valueOf(recordId));
        pdfPage.getParameters().put('senderId', safeValue(senderId));
        pdfPage.getParameters().put('sendDate', String.isBlank(sendDate) ? String.valueOf(Date.today()) : sendDate);
        pdfPage.getParameters().put('programStaffInitials', safeValue(normalizedProgramStaffInitials));

        Blob pdfBlob;
        if (Test.isRunningTest()) {
            pdfBlob = Blob.valueOf('Test PDF');
        } else {
            pdfBlob = pdfPage.getContentAsPDF();
        }

        Savepoint finalizeSavepoint = Database.setSavepoint();
        try {
            ContentVersion pdfVersion = new ContentVersion();
            pdfVersion.Title = 'Contractor Selected Form ' + System.now().format('MM-dd-yyyy') + '.pdf';
            pdfVersion.PathOnClient = 'ContractorSelectedForm.pdf';
            pdfVersion.VersionData = pdfBlob;
            pdfVersion.IsMajorVersion = true;
            insert pdfVersion;

            Id pdfDocumentId = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :pdfVersion.Id
                LIMIT 1
            ].ContentDocumentId;

            ContentDocumentLink pdfLink = new ContentDocumentLink();
            pdfLink.ContentDocumentId = pdfDocumentId;
            pdfLink.LinkedEntityId = recordId;
            pdfLink.ShareType = 'V';
            pdfLink.Visibility = 'AllUsers';
            insert pdfLink;

            buildertek__RFQ__c rfqUpdate = new buildertek__RFQ__c(
                Id = recordId,
                Contractor_Selected_Prgm_Staff_Initials__c = normalizedProgramStaffInitials,
                Contractor_Selected_Form_Submitted__c = true,
                Contractor_Selected_Form_Submitted_Date__c = Date.today()
            );
            update rfqUpdate;

            return 'Success';
        } catch (Exception ex) {
            Database.rollback(finalizeSavepoint);
            throw new AuraHandledException(ex.getMessage());
        }
    }

    public void initPdf() {
        vfRecordId = ApexPages.currentPage().getParameters().get('recordId');
        if (String.isBlank(vfRecordId)) {
            vfRecordId = ApexPages.currentPage().getParameters().get('id');
        }
        if (String.isBlank(vfRecordId)) {
            vfRecordId = ApexPages.currentPage().getParameters().get('Id');
        }

        vfSenderId = ApexPages.currentPage().getParameters().get('senderId');
        vfSendDate = ApexPages.currentPage().getParameters().get('sendDate');
        vfProgramStaffInitials = ApexPages.currentPage().getParameters().get('programStaffInitials');

        displayDate = String.isNotBlank(vfSendDate) ? formatShortDate(vfSendDate) : formatShortDate(Date.today());
        pdfVendorRows = new List<PdfVendorRow>();
        ownerNotes = '';
        homeownerSignatureUrl = '';
        programStaffSignatureUrl = '';

        if (isValidIdFormat(vfRecordId)) {
            Id recordId = (Id) vfRecordId;
            FormContext context = getFormContextInternal(recordId);
            propertyAddress = context != null ? context.propertyAddress : '';
            cityTown = context != null ? context.cityTown : '';
            zipCode = context != null ? context.zipCode : '';
            ownerNames = context != null ? context.ownerNames : '';
            ownerPhone = context != null ? context.phone : '';
            ownerEmail = context != null ? context.email : '';

            buildertek__RFQ__c rfq = getRfqStageRecord(recordId);
            ownerNotes = rfq != null ? rfq.Contractor_Selected_Homeowner_Notes__c : '';
            homeownerSignatureUrl = rfq != null
                ? resolveSignatureUrl(rfq.Contractor_Selected_HomeOwner_SignID__c)
                : '';
            programStaffSignatureUrl = rfq != null
                ? resolveSignatureUrl(rfq.Contractor_Selected_Prog_Staff_Sign_ID__c)
                : '';

            String programStaffInitials = String.isNotBlank(vfProgramStaffInitials)
                ? vfProgramStaffInitials
                : (rfq != null ? rfq.Contractor_Selected_Prgm_Staff_Initials__c : '');
            String homeownerInitials = rfq != null ? rfq.Contractor_Selected_HomeOwner_Initials__c : '';
            String selectedVendorId = rfq != null ? (String) rfq.Contractor_Selected_RFQ_To_Vendor__c : '';

            pdfVendorRows = buildPdfVendorRows(
                getRfqToVendors(recordId),
                selectedVendorId,
                homeownerInitials,
                programStaffInitials
            );
        } else {
            propertyAddress = '';
            cityTown = '';
            zipCode = '';
            ownerNames = '';
            ownerPhone = '';
            ownerEmail = '';
        }

        logoUrl = getLogoUrl();
    }

    public Boolean getHasPdfVendorRows() {
        return pdfVendorRows != null && !pdfVendorRows.isEmpty();
    }

    public Boolean getHasOwnerNotes() {
        return String.isNotBlank(ownerNotes);
    }

    public Boolean getHasHomeownerSignature() {
        return String.isNotBlank(homeownerSignatureUrl);
    }

    public Boolean getHasProgramStaffSignature() {
        return String.isNotBlank(programStaffSignatureUrl);
    }

    private static FormContext getFormContextInternal(Id recordId) {
        if (recordId == null) {
            return null;
        }

        Map<String, Schema.SObjectField> accountFieldMap = Account.SObjectType.getDescribe().fields.getMap();
        List<String> queryFields = new List<String>{
            'Id',
            'buildertek__Project__r.buildertek__Address__c',
            'buildertek__Project__r.buildertek__City_Text__c',
            'buildertek__Project__r.buildertek__Zip__c',
            'buildertek__Project__r.buildertek__Customer__r.Name',
            'buildertek__Project__r.buildertek__Customer__r.Phone'
        };

        Boolean hasPersonEmail = accountFieldMap.containsKey('PersonEmail');
        if (hasPersonEmail) {
            queryFields.add('buildertek__Project__r.buildertek__Customer__r.PersonEmail');
        }

        SObject rfqRecord = Database.query(
            'SELECT ' + String.join(queryFields, ',')
            + ' FROM buildertek__RFQ__c'
            + ' WHERE Id = :recordId'
            + ' LIMIT 1'
        );

        if (rfqRecord == null) {
            return null;
        }

        SObject projectRecord = rfqRecord.getSObject('buildertek__Project__r');
        SObject customerRecord = projectRecord != null ? projectRecord.getSObject('buildertek__Customer__r') : null;

        FormContext context = new FormContext();
        context.propertyAddress = projectRecord != null ? (String) projectRecord.get('buildertek__Address__c') : '';
        context.cityTown = projectRecord != null ? (String) projectRecord.get('buildertek__City_Text__c') : '';
        context.zipCode = projectRecord != null ? (String) projectRecord.get('buildertek__Zip__c') : '';
        context.ownerNames = customerRecord != null ? (String) customerRecord.get('Name') : '';
        context.phone = customerRecord != null ? (String) customerRecord.get('Phone') : '';
        context.email = hasPersonEmail && customerRecord != null ? (String) customerRecord.get('PersonEmail') : '';
        return context;
    }

    private static buildertek__RFQ__c getRfqStageRecord(Id recordId) {
        if (recordId == null) {
            return null;
        }

        List<buildertek__RFQ__c> rfqs = [
            SELECT Id,
                   Contractor_Selected_Form_Submitted__c,
                   Contractor_Selected_Form_Submitted_Date__c,
                   Contractor_Selected_RFQ_To_Vendor__c,
                   Contractor_Selected_HomeOwner_Initials__c,
                   Contractor_Selected_Homeowner_Notes__c,
                   Contractor_Selected_HomeOwner_SignID__c,
                   Contractor_Selected_HomeOwner_Sign_Date__c,
                   Contractor_Selected_Prgm_Staff_Initials__c,
                   Contractor_Selected_Prog_Staff_Sign_ID__c,
                   Contractor_Selected_Prog_Staff_Sign_Date__c,
                   Contractor_Selected_Prog_Staff_Req_Sent__c,
                   Contractor_Selected_Program_Staff_User__c,
                   Contractor_Selected_Program_Staff_User__r.Name,
                   Contractor_Selected_Program_Staff_User__r.Email,
                   Contractor_Selected_Program_Staff_Email__c
            FROM buildertek__RFQ__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        return rfqs.isEmpty() ? null : rfqs[0];
    }

    private static void validateHomeownerStageInput(
        buildertek__RFQ__c rfq,
        Id recordId,
        Id selectedVendorId,
        String homeownerInitials
    ) {
        if (rfq == null) {
            throw new AuraHandledException('The RFQ could not be found.');
        }

        if (rfq.Contractor_Selected_Form_Submitted__c) {
            throw new AuraHandledException('This Contractor Selected Form has already been finalized.');
        }

        if (isHomeownerStageComplete(rfq)) {
            throw new AuraHandledException('The homeowner stage has already been completed.');
        }

        if (selectedVendorId == null) {
            throw new AuraHandledException('Select exactly one contractor before submitting.');
        }

        List<buildertek__RFQ_To_Vendor__c> matchingRows = [
            SELECT Id
            FROM buildertek__RFQ_To_Vendor__c
            WHERE Id = :selectedVendorId
            AND buildertek__RFQ__c = :recordId
            LIMIT 1
        ];
        if (matchingRows.isEmpty()) {
            throw new AuraHandledException('The selected contractor does not belong to this RFQ.');
        }

        if (String.isBlank(rfq.Contractor_Selected_HomeOwner_SignID__c)) {
            throw new AuraHandledException('Homeowner signature is required.');
        }

        if (String.isBlank(rfq.Contractor_Selected_Program_Staff_Email__c)) {
            throw new AuraHandledException('A Program Representative contact must be selected before the homeowner stage can be submitted.');
        }
    }

    private static String sendProgramStaffStageEmail(
        buildertek__RFQ__c rfq,
        String senderId,
        String sendDate,
        String fromAddressId,
        String programRepresentativeName
    ) {
        if (rfq == null) {
            return 'The RFQ could not be found.';
        }

        String recipientEmail = String.isNotBlank(rfq.Contractor_Selected_Program_Staff_Email__c)
            ? rfq.Contractor_Selected_Program_Staff_Email__c.trim()
            : (rfq.Contractor_Selected_Program_Staff_User__r != null
                ? safeValue(rfq.Contractor_Selected_Program_Staff_User__r.Email).trim()
                : '');

        if (String.isBlank(recipientEmail)) {
            return 'The selected Program Representative does not have an email address.';
        }

        List<EmailTemplate> templates = [
            SELECT Subject, Body, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :PROGRAM_STAFF_TEMPLATE_NAME
            LIMIT 1
        ];

        String subjectLine = PROGRAM_STAFF_TEMPLATE_FALLBACK_SUBJECT;
        String htmlBody = '';
        if (!templates.isEmpty()) {
            EmailTemplate templateRecord = templates[0];
            if (String.isNotBlank(templateRecord.Subject)) {
                subjectLine = templateRecord.Subject;
            }
            htmlBody = String.isNotBlank(templateRecord.HtmlValue)
                ? templateRecord.HtmlValue
                : templateRecord.Body;
        }

        if (String.isBlank(htmlBody)) {
            htmlBody =
                '<p>Hello {!ContactName},</p>'
                + '<p>The homeowner has completed the Contractor Selected Form. Please {!URL} to review the selection and countersign the form.</p>'
                + '<p>Sincerely,<br/>{!$Organization.Street}<br/>{!$Organization.City}, {!$Organization.State}. {!$Organization.PostalCode}<br/>{!$Organization.Phone}</p>';
        }

        String representativeDisplayName = String.isNotBlank(programRepresentativeName)
            ? programRepresentativeName.trim()
            : (rfq.Contractor_Selected_Program_Staff_User__r != null
                ? rfq.Contractor_Selected_Program_Staff_User__r.Name
                : '');

        String stage2Link = buildPublicPageUrl(
            rfq.Id,
            String.isBlank(senderId) ? safeValue((String) rfq.Contractor_Selected_Program_Staff_User__c) : senderId,
            String.isBlank(sendDate) ? String.valueOf(Date.today()) : sendDate,
            representativeDisplayName
        );
        String linkMarkup = '<a href="' + stage2Link + '">Open Contractor Selected Form</a>';
        if (htmlBody.contains('{!URL}')) {
            htmlBody = htmlBody.replace('{!URL}', linkMarkup);
        } else {
            htmlBody += '<p>' + linkMarkup + '</p>';
        }

        htmlBody = applyOrganizationMergeFields(htmlBody);
        htmlBody = applyContactName(htmlBody, representativeDisplayName);

        Messaging.SingleEmailMessage emailMessage = new Messaging.SingleEmailMessage();
        emailMessage.setToAddresses(new List<String>{ recipientEmail });
        if (String.isNotBlank(fromAddressId)) {
            emailMessage.setOrgWideEmailAddressId(fromAddressId);
        }
        emailMessage.setSubject(subjectLine);
        emailMessage.setHtmlBody(htmlBody);
        emailMessage.setSaveAsActivity(false);
        emailMessage.setUseSignature(false);
        emailMessage.setWhatId(rfq.Id);

        Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { emailMessage });
        if (!results.isEmpty() && results[0].isSuccess()) {
            return 'Success';
        }

        if (!results.isEmpty() && results[0].getErrors() != null && !results[0].getErrors().isEmpty()) {
            return results[0].getErrors()[0].getMessage();
        }

        return 'Failed to send the Program Representative countersign email.';
    }

    private static void updateSignatureFields(Id recordId, String signatureLabel, Id contentVersionId) {
        if (recordId == null || contentVersionId == null) {
            return;
        }

        buildertek__RFQ__c rfqUpdate = new buildertek__RFQ__c(Id = recordId);
        Boolean shouldUpdate = false;

        if (signatureLabel == HOMEOWNER_SIGNATURE_LABEL) {
            rfqUpdate.Contractor_Selected_HomeOwner_SignID__c = contentVersionId;
            rfqUpdate.Contractor_Selected_HomeOwner_Sign_Date__c = Date.today();
            shouldUpdate = true;
        } else if (signatureLabel == PROGRAM_STAFF_SIGNATURE_LABEL) {
            rfqUpdate.Contractor_Selected_Prog_Staff_Sign_ID__c = contentVersionId;
            rfqUpdate.Contractor_Selected_Prog_Staff_Sign_Date__c = Date.today();
            shouldUpdate = true;
        }

        if (shouldUpdate) {
            update rfqUpdate;
        }
    }

    private static void linkContentToRfq(Id recordId, Id contentVersionId) {
        if (recordId == null || contentVersionId == null) {
            return;
        }

        try {
            Id contentDocumentId = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ].ContentDocumentId;

            if (contentDocumentId == null) {
                return;
            }

            ContentDocumentLink recordLink = new ContentDocumentLink();
            recordLink.ContentDocumentId = contentDocumentId;
            recordLink.LinkedEntityId = recordId;
            recordLink.ShareType = 'V';
            recordLink.Visibility = 'AllUsers';
            Database.insert(recordLink, false);
        } catch (Exception ex) {
            // Signature persistence should not fail just because the record link could not be created.
        }
    }

    private static String resolveSignatureUrl(String storedId) {
        String contentVersionId = resolveContentVersionId(storedId);
        if (String.isBlank(contentVersionId) || !isValidIdFormat(contentVersionId)) {
            return '';
        }

        List<ContentDistribution> distributions = [
            SELECT ContentDownloadUrl
            FROM ContentDistribution
            WHERE ContentVersionId = :contentVersionId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!distributions.isEmpty() && String.isNotBlank(distributions[0].ContentDownloadUrl)) {
            return distributions[0].ContentDownloadUrl;
        }

        return buildVersionDownloadUrl((Id) contentVersionId);
    }

    private static String buildPublicPageUrl(
        Id recordId,
        String senderId,
        String sendDate,
        String programRepresentativeName
    ) {
        String link = getConfirmationSiteUrl() + '/apex/ContractorSelectedForm'
            + '?recordId=' + EncodingUtil.urlEncode(String.valueOf(recordId), 'UTF-8')
            + '&isPreview=false'
            + '&senderId=' + EncodingUtil.urlEncode(safeValue(senderId), 'UTF-8')
            + '&sendDate=' + EncodingUtil.urlEncode(String.isBlank(sendDate) ? String.valueOf(Date.today()) : sendDate, 'UTF-8')
            + '&isProgramRepresentative=true';

        if (String.isNotBlank(programRepresentativeName)) {
            link += '&programRepresentativeName=' + EncodingUtil.urlEncode(programRepresentativeName, 'UTF-8');
        }

        return link;
    }

    private static String getConfirmationSiteUrl() {
        buildertek__ConfirmationSiteURL__c settings = buildertek__ConfirmationSiteURL__c.getOrgDefaults();
        if (settings != null && String.isNotBlank(settings.buildertek__Sites_URL__c)) {
            return normalizeBaseUrl(settings.buildertek__Sites_URL__c);
        }

        return normalizeBaseUrl(URL.getOrgDomainUrl().toExternalForm());
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

    private static String applyContactName(String emailBody, String contactName) {
        if (String.isBlank(emailBody) || String.isBlank(contactName)) {
            return emailBody;
        }

        return emailBody.replace('{!ContactName}', contactName);
    }

    private static List<PdfVendorRow> buildPdfVendorRows(
        List<buildertek__RFQ_To_Vendor__c> rfqToVendors,
        String selectedVendorId,
        String homeownerInitials,
        String programStaffInitials
    ) {
        List<PdfVendorRow> rows = new List<PdfVendorRow>();
        for (buildertek__RFQ_To_Vendor__c rfqToVendor : rfqToVendors) {
            PdfVendorRow row = new PdfVendorRow();
            row.id = (String) rfqToVendor.Id;
            row.contractorName = buildVendorName(rfqToVendor);
            row.bidAmount = buildBidAmount(rfqToVendor);
            row.bidLabel = buildBidLabel(rfqToVendor);
            row.selectionMark = row.id == selectedVendorId ? 'x' : '';
            row.homeownerInitials = row.id == selectedVendorId ? safeValue(homeownerInitials) : '';
            row.programStaffInitials = row.id == selectedVendorId ? safeValue(programStaffInitials) : '';
            rows.add(row);
        }
        return rows;
    }

    private static String buildBidLabel(buildertek__RFQ_To_Vendor__c rfqToVendor) {
        String vendorName = buildVendorName(rfqToVendor);
        String bidAmount = buildBidAmount(rfqToVendor);

        if (String.isBlank(bidAmount)) {
            return vendorName;
        }

        return vendorName + ' - ' + bidAmount;
    }

    private static String buildVendorName(buildertek__RFQ_To_Vendor__c rfqToVendor) {
        return rfqToVendor.buildertek__Vendor__r != null
            ? rfqToVendor.buildertek__Vendor__r.Name
            : rfqToVendor.Name;
    }

    private static String buildBidAmount(buildertek__RFQ_To_Vendor__c rfqToVendor) {
        if (rfqToVendor.buildertek__Vendor_Quote_Amount__c == null) {
            return '';
        }

        return rfqToVendor.buildertek__Vendor_Quote_Amount__c.format();
    }

    private static Boolean isHomeownerStageComplete(buildertek__RFQ__c rfq) {
        return rfq != null
            && rfq.Contractor_Selected_RFQ_To_Vendor__c != null
            && String.isNotBlank(rfq.Contractor_Selected_HomeOwner_SignID__c);
    }

    private static Boolean isProgramStaffAuthorized(buildertek__RFQ__c rfq, Boolean allowRepresentativeAccess) {
        if (allowRepresentativeAccess == true) {
            return true;
        }

        if (rfq == null || isGuestUser() || rfq.Contractor_Selected_Program_Staff_User__c == null) {
            return false;
        }

        return String.valueOf(rfq.Contractor_Selected_Program_Staff_User__c) == UserInfo.getUserId();
    }

    private static Boolean isGuestUser() {
        return UserInfo.getUserType() == 'Guest';
    }

    private static String normalizeSignatureLabel(String signatureLabel) {
        String trimmedLabel = String.isBlank(signatureLabel) ? '' : signatureLabel.trim().toLowerCase();
        if (trimmedLabel == 'program staff' || trimmedLabel == 'programstaff') {
            return PROGRAM_STAFF_SIGNATURE_LABEL;
        }

        return HOMEOWNER_SIGNATURE_LABEL;
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

    private static String buildVersionDownloadUrl(Id contentVersionId) {
        if (contentVersionId == null) {
            return '';
        }

        buildertek__ConfirmationSiteURL__c sitesUrl = buildertek__ConfirmationSiteURL__c.getOrgDefaults();
        String baseUrl = sitesUrl != null && String.isNotBlank(sitesUrl.buildertek__Sites_URL__c)
            ? normalizeBaseUrl(sitesUrl.buildertek__Sites_URL__c)
            : normalizeBaseUrl(URL.getOrgDomainUrl().toExternalForm());
        return baseUrl + '/sfc/servlet.shepherd/version/download/' + contentVersionId;
    }

    private static String resolveContentVersionId(String idValue) {
        if (String.isBlank(idValue) || !isValidIdFormat(idValue)) {
            return null;
        }

        List<ContentVersion> byVersion = [
            SELECT Id
            FROM ContentVersion
            WHERE Id = :idValue
            LIMIT 1
        ];
        if (!byVersion.isEmpty()) {
            return byVersion[0].Id;
        }

        List<ContentVersion> byDocument = [
            SELECT Id
            FROM ContentVersion
            WHERE ContentDocumentId = :idValue
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!byDocument.isEmpty()) {
            return byDocument[0].Id;
        }

        return null;
    }

    private static String formatShortDate(String rawValue) {
        if (String.isBlank(rawValue)) {
            return formatShortDate(Date.today());
        }

        String trimmed = rawValue.trim();
        String dateOnly = trimmed.contains(' ') ? trimmed.split(' ')[0] : trimmed;

        if (Pattern.matches('\\d{4}-\\d{2}-\\d{2}', dateOnly)) {
            List<String> parts = dateOnly.split('-');
            return formatShortDate(
                Date.newInstance(
                    Integer.valueOf(parts[0]),
                    Integer.valueOf(parts[1]),
                    Integer.valueOf(parts[2])
                )
            );
        }

        List<String> alternateParts = dateOnly.split('[-/]');
        if (alternateParts.size() == 3) {
            Integer month = Integer.valueOf(alternateParts[0]);
            Integer day = Integer.valueOf(alternateParts[1]);
            Integer year = Integer.valueOf(alternateParts[2]);
            return formatShortDate(Date.newInstance(year, month, day));
        }

        return trimmed;
    }

    private static String formatShortDate(Date value) {
        if (value == null) {
            return '';
        }

        return String.valueOf(value.month()) + '/'
            + String.valueOf(value.day()) + '/'
            + String.valueOf(value.year());
    }

    private static Boolean isValidIdFormat(String value) {
        if (String.isBlank(value)) {
            return false;
        }

        return Pattern.matches('^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$', value);
    }

    private static String safeValue(String value) {
        return value == null ? '' : value;
    }
}