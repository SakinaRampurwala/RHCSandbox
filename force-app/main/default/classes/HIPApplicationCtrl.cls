public without sharing class HIPApplicationCtrl {
    public String isPreview { get; set; }
    public String recordId { get; set; }
    public String senderId { get; set; }
    public String sendDate { get; set; }
    public String logoUrl { get; set; }
    public String vfApplicantSignatureUrl { get; set; }
    public String vfCoApplicantSignatureUrl { get; set; }
    public String vfApplicantPrintName { get; set; }
    public String vfCoApplicantPrintName { get; set; }
    public String vfApplicantSignDate { get; set; }
    public String vfCoApplicantSignDate { get; set; }
    public String currentRecordDate { get; set; }
    public String pdfApplicantName { get; set; }
    public String pdfPropertyAddress { get; set; }
    public String pdfMaritalStatus { get; set; }
    public String pdfHouseholdType { get; set; }
    public String pdfNumberOfUnitsInBuilding { get; set; }
    public String pdfFamilyHouseholdSize { get; set; }
    public String pdfHowManyDependents { get; set; }
    public String pdfHomeEverReceivedWeatherization { get; set; }
    public String pdfRaceEthnicityHead { get; set; }
    public String pdfRaceEthnicityCoApplicant { get; set; }
    public String pdfHasGalvanTies { get; set; }
    public String pdfCurrentHouseholdMonthlyDebt { get; set; }
    public List<PdfBorrowerData> pdfBorrowers { get; set; }
    public PdfFinancialData pdfFinancial { get; set; }
    public Set<String> pdfCheckedDocumentKeys { get; set; }

    public HIPApplicationCtrl() {
        Map<String, String> params = ApexPages.currentPage().getParameters();
        isPreview = params.get('isPreview');
        recordId = params.get('id');
        if (String.isBlank(recordId)) {
            recordId = params.get('recordId');
        }
        senderId = params.get('senderId');
        sendDate = params.get('sendDate');
        logoUrl = getLogoUrl();
        currentRecordDate = formatDisplayDate(Date.today());
        initializePdfSignatureData(params);
        initializePdfSavedData();
    }

    @AuraEnabled(cacheable=true)
    public static String getLogoUrl() {
        try {
            buildertek__ConfirmationSiteURL__c sitesUrl = buildertek__ConfirmationSiteURL__c.getOrgDefaults();
            String baseUrl = '';
            if (sitesUrl != null && String.isNotBlank(sitesUrl.buildertek__Sites_URL__c)) {
                baseUrl = sitesUrl.buildertek__Sites_URL__c;
            } else {
                baseUrl = URL.getOrgDomainUrl().toExternalForm();
            }

            List<Document> logoDocs = [SELECT Id FROM Document WHERE DeveloperName = 'Company_Logo' LIMIT 1];
            if (logoDocs.isEmpty()) {
                logoDocs = [SELECT Id FROM Document WHERE Name = 'BuildettekLogo' LIMIT 1];
            }
            if (logoDocs.isEmpty()) {
                return null;
            }
            return baseUrl + '/servlet/servlet.FileDownload?file=' + logoDocs[0].Id;
        } catch (Exception e) {
            return null;
        }
    }

    @AuraEnabled
    public static Map<String, Object> getInitialData(String recordId) {
        Map<String, Object> response = new Map<String, Object>();
        response.put('isSubmitted', false);
        response.put('submittedDate', '');
        response.put('submittedDateDisplay', '');
        response.put('applicantSignatureId', '');
        response.put('coApplicantSignatureId', '');
        response.put('applicantSignatureUrl', '');
        response.put('coApplicantSignatureUrl', '');
        response.put('applicantPrintName', '');
        response.put('coApplicantPrintName', '');
        response.put('applicantSignDate', '');
        response.put('coApplicantSignDate', '');
        response.put('applicantName', '');
        response.put('propertyAddress', '');
        response.put('files', new List<Map<String, Object>>());

        try {
            if (String.isNotBlank(recordId)) {
                Id accountRecordId = parseRecordId(recordId);
                List<Account> accounts = [
                    SELECT Id,
                        Name,
                        BillingStreet,
                        BillingCity,
                        BillingState,
                        BillingPostalCode,
                        BillingCountry,
                        ShippingStreet,
                        ShippingCity,
                        ShippingState,
                        ShippingPostalCode,
                        ShippingCountry,
                        HIP_Applicant_Sign_Id__c,
                        HIP_Co_Applicant_Sign_Id__c,
                        HIP_Submitted_Date__c
                    FROM Account
                    WHERE Id = :accountRecordId
                    LIMIT 1
                ];

                if (!accounts.isEmpty()) {
                    Account accountRecord = accounts[0];
                    response.put('isSubmitted', accountRecord.HIP_Submitted_Date__c != null);
                    response.put('submittedDate', accountRecord.HIP_Submitted_Date__c == null ? '' : String.valueOf(accountRecord.HIP_Submitted_Date__c));
                    response.put('submittedDateDisplay', formatDisplayDate(accountRecord.HIP_Submitted_Date__c));
                    response.put('applicantSignatureId', safe((String) accountRecord.HIP_Applicant_Sign_Id__c));
                    response.put('coApplicantSignatureId', safe((String) accountRecord.HIP_Co_Applicant_Sign_Id__c));
                    Map<String, String> applicantSignature = getStoredSignatureDisplayData(
                        (String) accountRecord.HIP_Applicant_Sign_Id__c,
                        'HIP Application - Applicant Signature',
                        accountRecord.HIP_Submitted_Date__c
                    );
                    Map<String, String> coApplicantSignature = getStoredSignatureDisplayData(
                        (String) accountRecord.HIP_Co_Applicant_Sign_Id__c,
                        'HIP Application - Co-Applicant Signature',
                        accountRecord.HIP_Submitted_Date__c
                    );
                    response.put('applicantSignatureUrl', applicantSignature.get('signatureUrl'));
                    response.put('coApplicantSignatureUrl', coApplicantSignature.get('signatureUrl'));
                    response.put('applicantPrintName', applicantSignature.get('printName'));
                    response.put('coApplicantPrintName', coApplicantSignature.get('printName'));
                    response.put('applicantSignDate', applicantSignature.get('signDate'));
                    response.put('coApplicantSignDate', coApplicantSignature.get('signDate'));
                    response.put('applicantName', safe(accountRecord.Name));
                    response.put('propertyAddress', formatAccountAddress(accountRecord));
                    response.put('files', getUploadedFiles(accountRecordId));
                    response.put('savedApplication', getSavedApplicationData(accountRecordId));
                }
            }

            return response;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to load HIP application data: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, String> uploadFile(
        String recordId,
        String fileName,
        String base64Data,
        String documentSection,
        String documentItemId,
        String documentLabel
    ) {
        try {
            if (String.isBlank(recordId) || String.isBlank(fileName) || String.isBlank(base64Data)) {
                throw new AuraHandledException('Record id, file name, and file data are required.');
            }

            Id accountRecordId = parseRecordId(recordId);
            if (isHipApplicationSubmitted(accountRecordId)) {
                throw new AuraHandledException('HIP Application has already been submitted. Files can only be viewed now.');
            }

            if (base64Data.contains(',')) {
                base64Data = base64Data.substringAfter(',');
            }

            ContentVersion versionRecord = new ContentVersion();
            versionRecord.Title = buildUploadTitle(fileName, documentLabel);
            versionRecord.PathOnClient = fileName;
            versionRecord.Description = buildUploadDescription(documentSection, documentItemId);
            versionRecord.VersionData = EncodingUtil.base64Decode(base64Data);
            insert versionRecord;

            versionRecord = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :versionRecord.Id
                LIMIT 1
            ];

            ContentDocumentLink linkRecord = new ContentDocumentLink();
            linkRecord.LinkedEntityId = accountRecordId;
            linkRecord.ContentDocumentId = versionRecord.ContentDocumentId;
            linkRecord.ShareType = 'V';
            linkRecord.Visibility = 'AllUsers';
            insert linkRecord;

            Map<String, String> uploadedFile = new Map<String, String>();
            uploadedFile.put('contentDocumentId', String.valueOf(versionRecord.ContentDocumentId));
            uploadedFile.put('contentVersionId', String.valueOf(versionRecord.Id));
            uploadedFile.put('fileName', fileName);
            uploadedFile.put('documentSection', safe(documentSection));
            uploadedFile.put('documentItemId', safe(documentItemId));
            uploadedFile.put('downloadUrl', getOrCreateDistributionUrl(versionRecord.Id));
            return uploadedFile;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to upload file: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void removeUploadedFile(String recordId, String contentDocumentId) {
        try {
            if (String.isBlank(recordId) || String.isBlank(contentDocumentId)) {
                throw new AuraHandledException('Record id and file id are required.');
            }

            Id accountRecordId = parseRecordId(recordId);
            if (isHipApplicationSubmitted(accountRecordId)) {
                throw new AuraHandledException('HIP Application has already been submitted. Files can only be viewed now.');
            }

            if (contentDocumentId.startsWith('068')) {
                List<ContentVersion> versions = [
                    SELECT ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :contentDocumentId
                    LIMIT 1
                ];

                if (!versions.isEmpty()) {
                    contentDocumentId = versions[0].ContentDocumentId;
                }
            }

            List<ContentDocumentLink> links = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :accountRecordId
                AND ContentDocumentId = :contentDocumentId
                LIMIT 1
            ];

            if (!links.isEmpty()) {
                delete links;
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to remove uploaded file: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> submitApplication(String payloadJson) {
        Savepoint sp = Database.setSavepoint();
        try {
            if (String.isBlank(payloadJson)) {
                throw new AuraHandledException('Application payload is required.');
            }

            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
            String accountId = stringValue(payload.get('accountId'));

            if (String.isBlank(accountId)) {
                throw new AuraHandledException('Account id is required.');
            }

            Id accountRecordId = parseRecordId(accountId);
            List<Account> accounts = [
                SELECT Id, HIP_Submitted_Date__c
                FROM Account
                WHERE Id = :accountRecordId
                LIMIT 1
                FOR UPDATE
            ];

            if (accounts.isEmpty()) {
                throw new AuraHandledException('Account record was not found.');
            }

            if (accounts[0].HIP_Submitted_Date__c != null) {
                throw new AuraHandledException('HIP Application has already been submitted for this Account.');
            }

            Map<String, Object> dtiPayload = objectMap(payload.get('debtToIncome'));
            buildertek__Debt_to_Income__c dti = new buildertek__Debt_to_Income__c();
            dti.Name = 'HIP Application ' + DateTime.now().format('MM-dd-yyyy');
            dti.buildertek__Customer_Account__c = accountRecordId;
            putDecimal(dti, 'buildertek__Number_of_Units_in_Building__c', dtiPayload.get('numberOfUnitsInBuilding'));
            putDecimal(dti, 'buildertek__Number_in_Household__c', dtiPayload.get('numberInHousehold'));
            putDecimal(dti, 'buildertek__Current_household_s_monthly_income__c', dtiPayload.get('currentHouseholdMonthlyDebt'));
            putString(dti, 'buildertek__Home_ever_received_weatherization__c', dtiPayload.get('homeEverReceivedWeatherization'));
            putString(dti, 'buildertek__Race_Ethnicity_of_Head_of_Household__c', dtiPayload.get('raceEthnicityHead'));
            putString(dti, 'buildertek__Race_Ethnicity_of_Co_Applicant__c', dtiPayload.get('raceEthnicityCoApplicant'));
            putString(dti, 'buildertek__In_the_last_twelve_months_has_anyone_in__c', dtiPayload.get('hasGalvanTies'));
            insert dti;

            List<buildertek__Borrower__c> borrowers = new List<buildertek__Borrower__c>();
            List<Object> borrowerPayloads = objectList(payload.get('borrowers'));
            Integer borrowerNumber = 1;

            for (Object borrowerItem : borrowerPayloads) {
                Map<String, Object> borrowerPayload = objectMap(borrowerItem);
                if (hasBorrowerData(borrowerPayload)) {
                    buildertek__Borrower__c borrower = new buildertek__Borrower__c();
                    borrower.buildertek__Debt_to_Income__c = dti.Id;
                    borrower.buildertek__Borrower_Account__c = accountRecordId;
                    String borrowerName = stringValue(borrowerPayload.get('name'));
                    borrower.Name = String.isBlank(borrowerName) ? 'HIP Borrower ' + borrowerNumber : borrowerName;
                    putString(borrower, 'buildertek__Marital_Status__c', borrowerPayload.get('maritalStatus'));
                    putString(borrower, 'buildertek__House__c', borrowerPayload.get('householdType'));
                    putString(borrower, 'buildertek__Email_Address__c', borrowerPayload.get('emailAddress'));
                    putString(borrower, 'buildertek__Relationship__c', borrowerPayload.get('relationship'));
                    putString(borrower, 'buildertek__Employer__c', borrowerPayload.get('employer'));
                    putString(borrower, 'buildertek__Position_Held__c', borrowerPayload.get('positionHeld'));
                    putString(borrower, 'buildertek__How_long_employed__c', borrowerPayload.get('howLongEmployed'));
                    putDate(borrower, 'buildertek__Date_of_Birth__c', borrowerPayload.get('dateOfBirth'));
                    putDecimal(borrower, 'buildertek__How_Many_Dependents__c', borrowerPayload.get('howManyDependents'));
                    putDecimal(borrower, 'buildertek__Number_in_HouseHold__c', borrowerPayload.get('numberInHousehold'));
                    putDecimal(borrower, 'buildertek__Pension__c', borrowerPayload.get('pension'));
                    putDecimal(borrower, 'buildertek__Social_Security_Disability__c', borrowerPayload.get('socialSecurityDisability'));
                    putDecimal(borrower, 'buildertek__Unemployment__c', borrowerPayload.get('unemployment'));
                    putDecimal(borrower, 'buildertek__Business_Income_Draw__c', borrowerPayload.get('selfEmployment'));
                    putDecimal(borrower, 'buildertek__Rental_Income__c', borrowerPayload.get('rentalIncome'));
                    putDecimal(borrower, 'buildertek__Food_Stamps__c', borrowerPayload.get('publicAssistance'));
                    putDecimal(borrower, 'buildertek__Salary_Wages__c', borrowerPayload.get('salaryWages'));
                    putDecimal(borrower, 'buildertek__Bank_and_Investment_Interest__c', borrowerPayload.get('bankAndInvestmentInterest'));
                    putDecimal(borrower, 'buildertek__Housing_Mortgage_Taxes_Insurance__c', borrowerPayload.get('housingMortgageTaxesInsurance'));
                    putDecimal(borrower, 'buildertek__Health_Insurance__c', borrowerPayload.get('healthInsurance'));
                    putDecimal(borrower, 'buildertek__Alimony_Child_Support__c', borrowerPayload.get('alimonyChildSupport'));
                    putDecimal(borrower, 'buildertek__Cable_Satellite_TV__c', borrowerPayload.get('cableSatelliteTv'));
                    putDecimal(borrower, 'buildertek__Car_Payments__c', borrowerPayload.get('carLoan'));
                    putDecimal(borrower, 'buildertek__Auto_Insurance__c', borrowerPayload.get('carInsurance'));
                    putDecimal(borrower, 'buildertek__Other_Expense__c', borrowerPayload.get('otherExpense'));
                    putDecimal(borrower, 'buildertek__Phone__c', borrowerPayload.get('telephone'));
                    putDecimal(borrower, 'buildertek__Utilities__c', borrowerPayload.get('gasElectric'));
                    putDecimal(borrower, 'buildertek__Food__c', borrowerPayload.get('food'));
                    putDecimal(borrower, 'buildertek__Entertainment__c', borrowerPayload.get('entertainment'));
                    putDecimal(borrower, 'buildertek__Clothing__c', borrowerPayload.get('clothing'));
                    putDecimal(borrower, 'buildertek__Total_Monthly_Income__c', borrowerPayload.get('totalMonthlyIncome'));
                    putDecimal(borrower, 'buildertek__Total_Living_Expenses__c', borrowerPayload.get('totalLivingExpenses'));
                    borrowers.add(borrower);
                    borrowerNumber++;
                }
            }

            if (!borrowers.isEmpty()) {
                insert borrowers;
            }

            Boolean coApplicantSignatureRequired = borrowers.size() > 1;
            Integer signatureFileCount = 0;
            Id applicantSignatureId;
            Id coApplicantSignatureId;
            List<Object> signaturePayloads = objectList(payload.get('signatures'));
            for (Object signatureItem : signaturePayloads) {
                Map<String, Object> signaturePayload = objectMap(signatureItem);
                String imageData = stringValue(signaturePayload.get('imageData'));
                String signatureKey = stringValue(signaturePayload.get('signatureKey'));

                if (String.isNotBlank(imageData)) {
                    Id signatureId = saveSignatureFile(
                        accountRecordId,
                        stringValue(signaturePayload.get('signatureLabel')),
                        stringValue(signaturePayload.get('printName')),
                        stringValue(signaturePayload.get('signDate')),
                        imageData
                    );

                    if (signatureKey == 'applicant') {
                        applicantSignatureId = signatureId;
                    } else if (signatureKey == 'coApplicant') {
                        coApplicantSignatureId = signatureId;
                    }

                    signatureFileCount++;
                }
            }

            if (applicantSignatureId == null) {
                throw new AuraHandledException('Applicant signature is required before submitting.');
            }

            if (coApplicantSignatureRequired && coApplicantSignatureId == null) {
                throw new AuraHandledException('Co-applicant signature is required when more than one adult is included.');
            }

            Account accountUpdate = new Account(Id = accountRecordId);
            accountUpdate.HIP_Applicant_Sign_Id__c = String.valueOf(applicantSignatureId);
            if (coApplicantSignatureId != null) {
                accountUpdate.HIP_Co_Applicant_Sign_Id__c = String.valueOf(coApplicantSignatureId);
            }
            accountUpdate.HIP_Submitted_Date__c = Date.today();
            update accountUpdate;

            Map<String, Object> response = new Map<String, Object>();
            response.put('debtToIncomeId', dti.Id);
            response.put('borrowerCount', borrowers.size());
            response.put('signatureFileCount', signatureFileCount);
            response.put('applicantSignatureId', String.valueOf(applicantSignatureId));
            response.put('coApplicantSignatureId', coApplicantSignatureId == null ? '' : String.valueOf(coApplicantSignatureId));
            response.put('submittedDate', String.valueOf(Date.today()));
            response.put('submittedDateDisplay', formatDisplayDate(Date.today()));
            response.put('success', true);
            return response;
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Unable to submit HIP application: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String saveApplicationPdf(Id recordId) {
        try {
            if (recordId == null) {
                throw new AuraHandledException('Account record id is required.');
            }

            PageReference pdfPage = Page.HIPApplicationAsPDF;
            pdfPage.getParameters().put('id', String.valueOf(recordId));
            pdfPage.getParameters().put('isPreview', 'false');

            Blob pdfBlob;
            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('Test PDF');
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }

            ContentVersion pdfVersion = new ContentVersion();
            pdfVersion.Title = 'HIP Application ' + System.now().format('MM-dd-yyyy') + '.pdf';
            pdfVersion.PathOnClient = 'HIPApplication.pdf';
            pdfVersion.VersionData = pdfBlob;
            pdfVersion.IsMajorVersion = true;
            insert pdfVersion;

            pdfVersion = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :pdfVersion.Id
                LIMIT 1
            ];

            ContentDocumentLink pdfLink = new ContentDocumentLink();
            pdfLink.ContentDocumentId = pdfVersion.ContentDocumentId;
            pdfLink.LinkedEntityId = recordId;
            pdfLink.ShareType = 'V';
            pdfLink.Visibility = 'AllUsers';
            insert pdfLink;

            String result = 'Success';
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to create HIP application PDF: ' + e.getMessage());
        }
    }

    private static List<Map<String, Object>> getUploadedFiles(Id accountRecordId) {
        List<Map<String, Object>> fileRows = new List<Map<String, Object>>();
        List<ContentDocumentLink> fileLinks = [
            SELECT ContentDocumentId,
                ContentDocument.Title,
                ContentDocument.FileExtension,
                ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :accountRecordId
            ORDER BY SystemModstamp DESC
            LIMIT 500
        ];

        Set<Id> latestVersionIds = new Set<Id>();
        for (ContentDocumentLink fileLink : fileLinks) {
            if (fileLink.ContentDocument.LatestPublishedVersionId != null) {
                latestVersionIds.add(fileLink.ContentDocument.LatestPublishedVersionId);
            }
        }

        Map<Id, ContentVersion> versionsByDocumentId = new Map<Id, ContentVersion>();
        if (!latestVersionIds.isEmpty()) {
            for (ContentVersion versionRecord : [
                SELECT Id, ContentDocumentId, Title, PathOnClient, Description
                FROM ContentVersion
                WHERE Id IN :latestVersionIds
            ]) {
                versionsByDocumentId.put(versionRecord.ContentDocumentId, versionRecord);
            }
        }

        Map<Id, String> downloadUrlsByVersionId = new Map<Id, String>();
        try {
            downloadUrlsByVersionId = getOrCreateDistributionUrls(latestVersionIds);
        } catch (Exception e) {
            downloadUrlsByVersionId = new Map<Id, String>();
        }

        for (ContentDocumentLink fileLink : fileLinks) {
            String documentTitle = fileLink.ContentDocument.Title;
            if (!isHipSignatureFile(documentTitle)) {
                ContentVersion versionRecord = versionsByDocumentId.get(fileLink.ContentDocumentId);
                Id versionId = versionRecord != null ? versionRecord.Id : fileLink.ContentDocument.LatestPublishedVersionId;
                Map<String, String> uploadMetadata = parseUploadDescription(versionRecord != null ? versionRecord.Description : '');
                Map<String, Object> fileRow = new Map<String, Object>();

                fileRow.put('id', String.valueOf(fileLink.ContentDocumentId));
                fileRow.put('serverFileId', String.valueOf(fileLink.ContentDocumentId));
                fileRow.put('contentDocumentId', String.valueOf(fileLink.ContentDocumentId));
                fileRow.put('contentVersionId', versionId == null ? '' : String.valueOf(versionId));
                fileRow.put('name', getDisplayFileName(versionRecord, documentTitle, fileLink.ContentDocument.FileExtension));
                fileRow.put('downloadUrl', getDownloadUrl(versionId, downloadUrlsByVersionId));
                fileRow.put('documentSection', uploadMetadata.get('documentSection'));
                fileRow.put('documentItemId', uploadMetadata.get('documentItemId'));
                fileRows.add(fileRow);
            }
        }

        return fileRows;
    }

    private static Map<String, Object> getSavedApplicationData(Id accountRecordId) {
        Map<String, Object> savedData = new Map<String, Object>();
        savedData.put('household', new Map<String, Object>());
        savedData.put('characteristics', new Map<String, Object>());
        savedData.put('debtSummary', new Map<String, Object>());
        savedData.put('financialAssessment', new Map<String, Object>());
        savedData.put('borrowers', new List<Map<String, Object>>());

        List<buildertek__Debt_to_Income__c> dtiRecords = [
            SELECT Id,
                buildertek__Number_of_Units_in_Building__c,
                buildertek__Number_in_Household__c,
                buildertek__Current_household_s_monthly_income__c,
                buildertek__Home_ever_received_weatherization__c,
                buildertek__Race_Ethnicity_of_Head_of_Household__c,
                buildertek__Race_Ethnicity_of_Co_Applicant__c,
                buildertek__In_the_last_twelve_months_has_anyone_in__c
            FROM buildertek__Debt_to_Income__c
            WHERE buildertek__Customer_Account__c = :accountRecordId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (dtiRecords.isEmpty()) {
            return savedData;
        }

        buildertek__Debt_to_Income__c dti = dtiRecords[0];
        Map<String, Object> household = new Map<String, Object>();
        household.put('numberOfUnitsInBuilding', stringValue(dti.buildertek__Number_of_Units_in_Building__c));
        household.put('familyHouseholdSize', stringValue(dti.buildertek__Number_in_Household__c));
        household.put('homeEverReceivedWeatherization', safe((String) dti.buildertek__Home_ever_received_weatherization__c));
        savedData.put('household', household);

        Map<String, Object> characteristics = new Map<String, Object>();
        characteristics.put('raceEthnicityHead', safe((String) dti.buildertek__Race_Ethnicity_of_Head_of_Household__c));
        characteristics.put('raceEthnicityCoApplicant', safe((String) dti.buildertek__Race_Ethnicity_of_Co_Applicant__c));
        characteristics.put('hasGalvanTies', safe((String) dti.buildertek__In_the_last_twelve_months_has_anyone_in__c));
        savedData.put('characteristics', characteristics);

        Map<String, Object> debtSummary = new Map<String, Object>();
        debtSummary.put('currentHouseholdMonthlyDebt', stringValue(dti.buildertek__Current_household_s_monthly_income__c));
        savedData.put('debtSummary', debtSummary);

        List<Map<String, Object>> borrowerRows = new List<Map<String, Object>>();
        List<buildertek__Borrower__c> borrowerRecords = [
            SELECT Id,
                Name,
                buildertek__Marital_Status__c,
                buildertek__House__c,
                buildertek__Email_Address__c,
                buildertek__Relationship__c,
                buildertek__Employer__c,
                buildertek__Position_Held__c,
                buildertek__How_long_employed__c,
                buildertek__Date_of_Birth__c,
                buildertek__How_Many_Dependents__c,
                buildertek__Number_in_HouseHold__c,
                buildertek__Pension__c,
                buildertek__Social_Security_Disability__c,
                buildertek__Unemployment__c,
                buildertek__Business_Income_Draw__c,
                buildertek__Rental_Income__c,
                buildertek__Food_Stamps__c,
                buildertek__Salary_Wages__c,
                buildertek__Bank_and_Investment_Interest__c,
                buildertek__Housing_Mortgage_Taxes_Insurance__c,
                buildertek__Health_Insurance__c,
                buildertek__Alimony_Child_Support__c,
                buildertek__Cable_Satellite_TV__c,
                buildertek__Car_Payments__c,
                buildertek__Auto_Insurance__c,
                buildertek__Other_Expense__c,
                buildertek__Phone__c,
                buildertek__Utilities__c,
                buildertek__Food__c,
                buildertek__Entertainment__c,
                buildertek__Clothing__c,
                buildertek__Total_Monthly_Income__c,
                buildertek__Total_Living_Expenses__c
            FROM buildertek__Borrower__c
            WHERE buildertek__Debt_to_Income__c = :dti.Id
            ORDER BY CreatedDate ASC
            LIMIT 20
        ];

        for (buildertek__Borrower__c borrower : borrowerRecords) {
            Map<String, Object> borrowerRow = new Map<String, Object>();
            borrowerRow.put('id', String.valueOf(borrower.Id));
            borrowerRow.put('name', safe(borrower.Name));
            borrowerRow.put('maritalStatus', safe((String) borrower.buildertek__Marital_Status__c));
            borrowerRow.put('householdType', safe((String) borrower.buildertek__House__c));
            borrowerRow.put('emailAddress', safe((String) borrower.buildertek__Email_Address__c));
            borrowerRow.put('relationship', safe((String) borrower.buildertek__Relationship__c));
            borrowerRow.put('employer', safe((String) borrower.buildertek__Employer__c));
            borrowerRow.put('positionHeld', safe((String) borrower.buildertek__Position_Held__c));
            borrowerRow.put('howLongEmployed', safe((String) borrower.buildertek__How_long_employed__c));
            borrowerRow.put('dateOfBirth', borrower.buildertek__Date_of_Birth__c == null ? '' : String.valueOf(borrower.buildertek__Date_of_Birth__c));
            borrowerRow.put('howManyDependents', stringValue(borrower.buildertek__How_Many_Dependents__c));
            borrowerRow.put('numberInHousehold', stringValue(borrower.buildertek__Number_in_HouseHold__c));
            borrowerRow.put('pension', stringValue(borrower.buildertek__Pension__c));
            borrowerRow.put('socialSecurityDisability', stringValue(borrower.buildertek__Social_Security_Disability__c));
            borrowerRow.put('unemployment', stringValue(borrower.buildertek__Unemployment__c));
            borrowerRow.put('selfEmployment', stringValue(borrower.buildertek__Business_Income_Draw__c));
            borrowerRow.put('rentalIncome', stringValue(borrower.buildertek__Rental_Income__c));
            borrowerRow.put('publicAssistance', stringValue(borrower.buildertek__Food_Stamps__c));
            borrowerRow.put('employmentGrossMonthlyAmount', stringValue(borrower.buildertek__Salary_Wages__c));
            borrowerRow.put('interestIncome', stringValue(borrower.buildertek__Bank_and_Investment_Interest__c));
            borrowerRow.put('alimonyChildSupport', stringValue(borrower.buildertek__Alimony_Child_Support__c));
            borrowerRows.add(borrowerRow);
        }
        savedData.put('borrowers', borrowerRows);

        if (!borrowerRecords.isEmpty()) {
            buildertek__Borrower__c borrower = borrowerRecords[0];
            Map<String, Object> financialAssessment = new Map<String, Object>();
            financialAssessment.put('salaryWages', stringValue(borrower.buildertek__Salary_Wages__c));
            financialAssessment.put('bankAndInvestmentInterest', stringValue(borrower.buildertek__Bank_and_Investment_Interest__c));
            financialAssessment.put('totalMonthlyIncome', stringValue(borrower.buildertek__Total_Monthly_Income__c));
            financialAssessment.put('housingMortgageTaxesInsurance', stringValue(borrower.buildertek__Housing_Mortgage_Taxes_Insurance__c));
            financialAssessment.put('carLoan', stringValue(borrower.buildertek__Car_Payments__c));
            financialAssessment.put('carInsurance', stringValue(borrower.buildertek__Auto_Insurance__c));
            financialAssessment.put('healthInsurance', stringValue(borrower.buildertek__Health_Insurance__c));
            financialAssessment.put('cableSatelliteTv', stringValue(borrower.buildertek__Cable_Satellite_TV__c));
            financialAssessment.put('gasElectric', stringValue(borrower.buildertek__Utilities__c));
            financialAssessment.put('telephone', stringValue(borrower.buildertek__Phone__c));
            financialAssessment.put('food', stringValue(borrower.buildertek__Food__c));
            financialAssessment.put('entertainment', stringValue(borrower.buildertek__Entertainment__c));
            financialAssessment.put('clothing', stringValue(borrower.buildertek__Clothing__c));
            financialAssessment.put('otherExpense', stringValue(borrower.buildertek__Other_Expense__c));
            financialAssessment.put('alimonyChildSupport', stringValue(borrower.buildertek__Alimony_Child_Support__c));
            financialAssessment.put('totalLivingExpenses', stringValue(borrower.buildertek__Total_Living_Expenses__c));
            savedData.put('financialAssessment', financialAssessment);
        }

        return savedData;
    }

    private static Boolean isHipApplicationSubmitted(Id accountRecordId) {
        List<Account> accounts = [
            SELECT HIP_Submitted_Date__c
            FROM Account
            WHERE Id = :accountRecordId
            LIMIT 1
        ];

        return !accounts.isEmpty() && accounts[0].HIP_Submitted_Date__c != null;
    }

    private static Id parseRecordId(String recordId) {
        try {
            Id parsedId = Id.valueOf(recordId);
            String accountPrefix = Account.SObjectType.getDescribe().getKeyPrefix();
            if (!String.valueOf(parsedId).startsWith(accountPrefix)) {
                throw new AuraHandledException('Valid Account id is required.');
            }
            return parsedId;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Valid Account id is required.');
        }
    }

    private static String formatAccountAddress(Account accountRecord) {
        String billingAddress = formatOneLineAddress(
            accountRecord.BillingStreet,
            accountRecord.BillingCity,
            accountRecord.BillingState,
            accountRecord.BillingPostalCode,
            accountRecord.BillingCountry
        );

        if (String.isNotBlank(billingAddress)) {
            return billingAddress;
        }

        return formatOneLineAddress(
            accountRecord.ShippingStreet,
            accountRecord.ShippingCity,
            accountRecord.ShippingState,
            accountRecord.ShippingPostalCode,
            accountRecord.ShippingCountry
        );
    }

    private static String formatOneLineAddress(String street, String city, String state, String postalCode, String country) {
        List<String> addressParts = new List<String>();
        List<String> localityParts = new List<String>();

        if (String.isNotBlank(street)) {
            addressParts.add(street.trim());
        }
        if (String.isNotBlank(city)) {
            localityParts.add(city.trim());
        }
        if (String.isNotBlank(state)) {
            localityParts.add(state.trim());
        }
        if (String.isNotBlank(postalCode)) {
            localityParts.add(postalCode.trim());
        }
        if (!localityParts.isEmpty()) {
            addressParts.add(String.join(localityParts, ', '));
        }
        if (String.isNotBlank(country)) {
            addressParts.add(country.trim());
        }

        return String.join(addressParts, ', ');
    }

    private static String buildUploadTitle(String fileName, String documentLabel) {
        String baseFileName = fileName;
        Integer extensionIndex = String.isBlank(baseFileName) ? -1 : baseFileName.lastIndexOf('.');
        if (extensionIndex > 0) {
            baseFileName = baseFileName.substring(0, extensionIndex);
        }

        String safeLabel = String.isBlank(documentLabel) ? 'Document' : documentLabel.trim();
        return trimToLength('HIP Application - ' + safeLabel + ' - ' + baseFileName, 240);
    }

    private static String buildUploadDescription(String documentSection, String documentItemId) {
        return 'HIP_APPLICATION_DOCUMENT|' + safe(documentSection) + '|' + safe(documentItemId);
    }

    private static Map<String, String> parseUploadDescription(String description) {
        Map<String, String> metadata = new Map<String, String>();
        metadata.put('documentSection', '');
        metadata.put('documentItemId', '');

        if (String.isNotBlank(description) && description.startsWith('HIP_APPLICATION_DOCUMENT|')) {
            List<String> parts = description.split('\\|');
            if (parts.size() > 1) {
                metadata.put('documentSection', parts[1]);
            }
            if (parts.size() > 2) {
                metadata.put('documentItemId', parts[2]);
            }
        }

        return metadata;
    }

    private static String getDisplayFileName(ContentVersion versionRecord, String documentTitle, String fileExtension) {
        if (versionRecord != null && String.isNotBlank(versionRecord.PathOnClient)) {
            return versionRecord.PathOnClient;
        }

        String displayName = String.isBlank(documentTitle) ? 'Uploaded file' : documentTitle;
        if (String.isNotBlank(fileExtension) && !displayName.toLowerCase().endsWith('.' + fileExtension.toLowerCase())) {
            displayName += '.' + fileExtension;
        }

        return displayName;
    }

    private static Boolean isHipSignatureFile(String documentTitle) {
        return String.isNotBlank(documentTitle)
            && (documentTitle.startsWith('HIP Application - Applicant Signature')
                || documentTitle.startsWith('HIP Application - Co-Applicant Signature'));
    }

    private static String buildVersionDownloadUrl(Id contentVersionId) {
        return '/sfc/servlet.shepherd/version/download/' + String.valueOf(contentVersionId);
    }

    private static String getDownloadUrl(Id contentVersionId, Map<Id, String> downloadUrlsByVersionId) {
        if (contentVersionId == null) {
            return '';
        }

        if (downloadUrlsByVersionId != null && String.isNotBlank(downloadUrlsByVersionId.get(contentVersionId))) {
            return downloadUrlsByVersionId.get(contentVersionId);
        }

        return buildVersionDownloadUrl(contentVersionId);
    }

    private static String trimToLength(String value, Integer maxLength) {
        String textValue = safe(value);
        if (textValue.length() > maxLength) {
            textValue = textValue.substring(0, maxLength);
        }
        return textValue;
    }

    private static String safe(String value) {
        return String.isBlank(value) ? '' : value.trim();
    }

    private static Map<String, Object> objectMap(Object value) {
        if (value instanceof Map<String, Object>) {
            return (Map<String, Object>) value;
        }
        return new Map<String, Object>();
    }

    private static List<Object> objectList(Object value) {
        if (value instanceof List<Object>) {
            return (List<Object>) value;
        }
        return new List<Object>();
    }

    private static String stringValue(Object value) {
        if (value == null) {
            return null;
        }
        return String.valueOf(value).trim();
    }

    private static String moneyValue(Object value) {
        String textValue = stringValue(value);
        String formattedValue = '';
        if (String.isNotBlank(textValue)) {
            try {
                Decimal numericValue = decimalValue(textValue);
                if (numericValue != null) {
                    Decimal roundedValue = numericValue.setScale(2);
                    formattedValue = roundedValue.format();
                }
            } catch (Exception e) {
                formattedValue = textValue;
            }
        }
        return formattedValue;
    }

    private static List<PdfAssetData> pdfAssetRows(Object value) {
        List<PdfAssetData> assetRows = new List<PdfAssetData>();
        for (Object assetItem : objectList(value)) {
            Map<String, Object> assetMap = objectMap(assetItem);
            PdfAssetData assetRow = new PdfAssetData();
            assetRow.accountType = stringValue(assetMap.get('accountType'));
            assetRow.accountNumber = stringValue(assetMap.get('accountNumber'));
            assetRow.interestRate = stringValue(assetMap.get('interestRate'));
            assetRow.institutionName = stringValue(assetMap.get('institutionName'));
            assetRow.amount = moneyValue(assetMap.get('amount'));
            assetRows.add(assetRow);
        }

        if (assetRows.isEmpty()) {
            List<String> accountTypes = new List<String>{
                'Checking',
                'Savings',
                'CDs',
                'Credit Union',
                'Digital Assets (VenMo, Zelle, etc.)',
                'Life Insurance (whole life only)',
                'Stocks',
                'Trust Account',
                'Other (specify)'
            };
            for (String accountType : accountTypes) {
                PdfAssetData assetRow = new PdfAssetData();
                assetRow.accountType = accountType;
                assetRows.add(assetRow);
            }
        }

        return assetRows;
    }

    private static Decimal decimalValue(Object value) {
        String textValue = stringValue(value);
        if (String.isBlank(textValue)) {
            return null;
        }
        textValue = textValue.replace('$', '').replace(',', '');
        return Decimal.valueOf(textValue);
    }

    private static Date dateValue(Object value) {
        String textValue = stringValue(value);
        if (String.isBlank(textValue)) {
            return null;
        }
        return Date.valueOf(textValue);
    }

    private static void putString(SObject record, String fieldName, Object value) {
        String textValue = stringValue(value);
        if (String.isNotBlank(textValue)) {
            record.put(fieldName, textValue);
        }
    }

    private static void putDecimal(SObject record, String fieldName, Object value) {
        Decimal numericValue = decimalValue(value);
        if (numericValue != null) {
            record.put(fieldName, numericValue);
        }
    }

    private static void putDate(SObject record, String fieldName, Object value) {
        Date dateFieldValue = dateValue(value);
        if (dateFieldValue != null) {
            record.put(fieldName, dateFieldValue);
        }
    }

    private static Id saveSignatureFile(Id accountId, String signatureLabel, String printName, String signDate, String imageData) {
        if (imageData.contains(',')) {
            imageData = imageData.substringAfter(',');
        }

        String safeLabel = String.isBlank(signatureLabel) ? 'Signature' : signatureLabel;
        String title = 'HIP Application - ' + safeLabel;

        if (String.isNotBlank(printName)) {
            title += ' - ' + printName;
        }

        if (String.isNotBlank(signDate)) {
            title += ' - ' + signDate;
        }

        if (title.length() > 240) {
            title = title.substring(0, 240);
        }

        ContentVersion versionRecord = new ContentVersion();
        versionRecord.Title = title;
        versionRecord.PathOnClient = title + '.png';
        versionRecord.VersionData = EncodingUtil.base64Decode(imageData);
        insert versionRecord;

        versionRecord = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :versionRecord.Id
            LIMIT 1
        ];

        ContentDocumentLink linkRecord = new ContentDocumentLink();
        linkRecord.LinkedEntityId = accountId;
        linkRecord.ContentDocumentId = versionRecord.ContentDocumentId;
        linkRecord.ShareType = 'V';
        linkRecord.Visibility = 'AllUsers';
        insert linkRecord;

        return versionRecord.Id;
    }

    private void initializePdfSavedData() {
        pdfBorrowers = new List<PdfBorrowerData>();
        pdfFinancial = new PdfFinancialData();
        pdfCheckedDocumentKeys = new Set<String>();
        pdfApplicantName = '';
        pdfPropertyAddress = '';
        pdfMaritalStatus = '';
        pdfHouseholdType = '';
        pdfNumberOfUnitsInBuilding = '';
        pdfFamilyHouseholdSize = '';
        pdfHowManyDependents = '';
        pdfHomeEverReceivedWeatherization = '';
        pdfRaceEthnicityHead = '';
        pdfRaceEthnicityCoApplicant = '';
        pdfHasGalvanTies = '';
        pdfCurrentHouseholdMonthlyDebt = '';

        if (isPdfRequest() && String.isNotBlank(recordId) && isValidIdFormat(recordId)) {
            try {
                Id accountRecordId = Id.valueOf(recordId);
                List<Account> accounts = [
                    SELECT Name,
                        BillingStreet,
                        BillingCity,
                        BillingState,
                        BillingPostalCode,
                        BillingCountry,
                        ShippingStreet,
                        ShippingCity,
                        ShippingState,
                        ShippingPostalCode,
                        ShippingCountry
                    FROM Account
                    WHERE Id = :accountRecordId
                    LIMIT 1
                ];

                if (!accounts.isEmpty()) {
                    pdfApplicantName = safe(accounts[0].Name);
                    pdfPropertyAddress = formatAccountAddress(accounts[0]);
                }

                Map<String, Object> savedData = getSavedApplicationData(accountRecordId);
                initializePdfDocumentCheckMarks(accountRecordId);
                Map<String, Object> householdMap = objectMap(savedData.get('household'));
                pdfNumberOfUnitsInBuilding = stringValue(householdMap.get('numberOfUnitsInBuilding'));
                pdfFamilyHouseholdSize = stringValue(householdMap.get('familyHouseholdSize'));
                pdfHomeEverReceivedWeatherization = stringValue(householdMap.get('homeEverReceivedWeatherization'));

                Map<String, Object> characteristicsMap = objectMap(savedData.get('characteristics'));
                pdfRaceEthnicityHead = stringValue(characteristicsMap.get('raceEthnicityHead'));
                pdfRaceEthnicityCoApplicant = stringValue(characteristicsMap.get('raceEthnicityCoApplicant'));
                pdfHasGalvanTies = stringValue(characteristicsMap.get('hasGalvanTies'));

                Map<String, Object> debtSummaryMap = objectMap(savedData.get('debtSummary'));
                pdfCurrentHouseholdMonthlyDebt = moneyValue(debtSummaryMap.get('currentHouseholdMonthlyDebt'));

                for (Object borrowerItem : objectList(savedData.get('borrowers'))) {
                    Map<String, Object> borrowerMap = objectMap(borrowerItem);
                    PdfBorrowerData borrower = new PdfBorrowerData();
                    borrower.roleLabel = pdfBorrowers.isEmpty()
                        ? 'Adult One'
                        : (pdfBorrowers.size() == 1 ? 'Adult Two' : 'Additional Adult ' + String.valueOf(pdfBorrowers.size() + 1));
                    borrower.name = stringValue(borrowerMap.get('name'));
                    borrower.dateOfBirth = formatDateText(stringValue(borrowerMap.get('dateOfBirth')));
                    borrower.emailAddress = stringValue(borrowerMap.get('emailAddress'));
                    borrower.relationship = stringValue(borrowerMap.get('relationship'));
                    borrower.employer = stringValue(borrowerMap.get('employer'));
                    borrower.positionHeld = stringValue(borrowerMap.get('positionHeld'));
                    borrower.howLongEmployed = stringValue(borrowerMap.get('howLongEmployed'));
                    borrower.employmentGrossMonthlyAmount = moneyValue(borrowerMap.get('employmentGrossMonthlyAmount'));
                    borrower.pension = moneyValue(borrowerMap.get('pension'));
                    borrower.socialSecurityDisability = moneyValue(borrowerMap.get('socialSecurityDisability'));
                    borrower.unemployment = moneyValue(borrowerMap.get('unemployment'));
                    borrower.selfEmployment = moneyValue(borrowerMap.get('selfEmployment'));
                    borrower.rentalIncome = moneyValue(borrowerMap.get('rentalIncome'));
                    borrower.alimonyChildSupport = moneyValue(borrowerMap.get('alimonyChildSupport'));
                    borrower.investmentIncome = moneyValue(borrowerMap.get('investmentIncome'));
                    borrower.interestIncome = moneyValue(borrowerMap.get('interestIncome'));
                    borrower.publicAssistance = moneyValue(borrowerMap.get('publicAssistance'));
                    borrower.otherIncome = moneyValue(borrowerMap.get('otherIncome'));
                    borrower.assets = pdfAssetRows(borrowerMap.get('assets'));
                    pdfBorrowers.add(borrower);

                    if (pdfBorrowers.size() == 1) {
                        pdfMaritalStatus = stringValue(borrowerMap.get('maritalStatus'));
                        pdfHouseholdType = stringValue(borrowerMap.get('householdType'));
                        pdfHowManyDependents = stringValue(borrowerMap.get('howManyDependents'));
                    }
                }

                Map<String, Object> financialMap = objectMap(savedData.get('financialAssessment'));
                pdfFinancial.salaryWages = moneyValue(financialMap.get('salaryWages'));
                pdfFinancial.bankAndInvestmentInterest = moneyValue(financialMap.get('bankAndInvestmentInterest'));
                pdfFinancial.totalMonthlyIncome = moneyValue(financialMap.get('totalMonthlyIncome'));
                pdfFinancial.housingMortgageTaxesInsurance = moneyValue(financialMap.get('housingMortgageTaxesInsurance'));
                pdfFinancial.carLoan = moneyValue(financialMap.get('carLoan'));
                pdfFinancial.carInsurance = moneyValue(financialMap.get('carInsurance'));
                pdfFinancial.healthInsurance = moneyValue(financialMap.get('healthInsurance'));
                pdfFinancial.cableSatelliteTv = moneyValue(financialMap.get('cableSatelliteTv'));
                pdfFinancial.gasElectric = moneyValue(financialMap.get('gasElectric'));
                pdfFinancial.telephone = moneyValue(financialMap.get('telephone'));
                pdfFinancial.food = moneyValue(financialMap.get('food'));
                pdfFinancial.entertainment = moneyValue(financialMap.get('entertainment'));
                pdfFinancial.clothing = moneyValue(financialMap.get('clothing'));
                pdfFinancial.otherExpense = moneyValue(financialMap.get('otherExpense'));
                pdfFinancial.alimonyChildSupport = moneyValue(financialMap.get('alimonyChildSupport'));
                pdfFinancial.totalLivingExpenses = moneyValue(financialMap.get('totalLivingExpenses'));
            } catch (Exception e) {
                // Keep the PDF printable even when saved child record data is not available.
            }
        }

        if (pdfBorrowers.isEmpty()) {
            PdfBorrowerData borrower = new PdfBorrowerData();
            borrower.roleLabel = 'Adult One';
            borrower.assets = pdfAssetRows(null);
            pdfBorrowers.add(borrower);
        }
    }

    private void initializePdfDocumentCheckMarks(Id accountRecordId) {
        Set<Id> latestVersionIds = new Set<Id>();
        for (ContentDocumentLink fileLink : [
            SELECT ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :accountRecordId
            LIMIT 500
        ]) {
            if (fileLink.ContentDocument.LatestPublishedVersionId != null) {
                latestVersionIds.add(fileLink.ContentDocument.LatestPublishedVersionId);
            }
        }

        if (latestVersionIds.isEmpty()) {
            return;
        }

        for (ContentVersion versionRecord : [
            SELECT Description
            FROM ContentVersion
            WHERE Id IN :latestVersionIds
        ]) {
            Map<String, String> uploadMetadata = parseUploadDescription(versionRecord.Description);
            String documentSection = uploadMetadata.get('documentSection');
            String documentItemId = uploadMetadata.get('documentItemId');

            if (String.isNotBlank(documentSection) && String.isNotBlank(documentItemId)) {
                pdfCheckedDocumentKeys.add(documentSection + '|' + documentItemId);
            }
        }
    }

    private String getPdfDocumentMark(String documentSection, String documentItemId) {
        String mark = '';
        String documentKey = documentSection + '|' + documentItemId;
        if (pdfCheckedDocumentKeys != null && pdfCheckedDocumentKeys.contains(documentKey)) {
            mark = getPdfCheckedMark();
        }
        return mark;
    }

    private String getPdfCheckedMark() {
        String mark = '&#10004;';
        return mark;
    }

    private String getPdfDocumentCheckClass(String documentSection, String documentItemId) {
        String className = '';
        String documentKey = documentSection + '|' + documentItemId;
        if (pdfCheckedDocumentKeys != null && pdfCheckedDocumentKeys.contains(documentKey)) {
            className = 'pdf-check-checked';
        }
        return className;
    }

    public String getPdfApplicationHomeOwnershipMark() {
        String mark = getPdfDocumentMark('application', 'homeOwnership');
        return mark;
    }

    public String getPdfApplicationHomeOwnershipClass() {
        String className = getPdfDocumentCheckClass('application', 'homeOwnership');
        return className;
    }

    public String getPdfApplicationHomeownersInsuranceMark() {
        String mark = getPdfDocumentMark('application', 'homeownersInsurance');
        return mark;
    }

    public String getPdfApplicationHomeownersInsuranceClass() {
        String className = getPdfDocumentCheckClass('application', 'homeownersInsurance');
        return className;
    }

    public String getPdfApplicationTaxReceiptMark() {
        String mark = getPdfDocumentMark('application', 'taxReceipt');
        return mark;
    }

    public String getPdfApplicationTaxReceiptClass() {
        String className = getPdfDocumentCheckClass('application', 'taxReceipt');
        return className;
    }

    public String getPdfApplicationMortgageStatementMark() {
        String mark = getPdfDocumentMark('application', 'mortgageStatement');
        return mark;
    }

    public String getPdfApplicationMortgageStatementClass() {
        String className = getPdfDocumentCheckClass('application', 'mortgageStatement');
        return className;
    }

    public String getPdfAdultIncomeProofMark() {
        String mark = getPdfDocumentMark('adult', 'incomeProof');
        return mark;
    }

    public String getPdfAdultIncomeProofClass() {
        String className = getPdfDocumentCheckClass('adult', 'incomeProof');
        return className;
    }

    public String getPdfAdultFederalTaxReturnsMark() {
        String mark = getPdfDocumentMark('adult', 'federalTaxReturns');
        return mark;
    }

    public String getPdfAdultFederalTaxReturnsClass() {
        String className = getPdfDocumentCheckClass('adult', 'federalTaxReturns');
        return className;
    }

    public String getPdfAdultBankStatementsMark() {
        String mark = getPdfDocumentMark('adult', 'bankStatements');
        return mark;
    }

    public String getPdfAdultBankStatementsClass() {
        String className = getPdfDocumentCheckClass('adult', 'bankStatements');
        return className;
    }

    public String getPdfAdultLifeInsuranceMark() {
        String mark = getPdfDocumentMark('adult', 'lifeInsurance');
        return mark;
    }

    public String getPdfAdultLifeInsuranceClass() {
        String className = getPdfDocumentCheckClass('adult', 'lifeInsurance');
        return className;
    }

    public String getPdfAdultPaymentAppsMark() {
        String mark = getPdfDocumentMark('adult', 'paymentApps');
        return mark;
    }

    public String getPdfAdultPaymentAppsClass() {
        String className = getPdfDocumentCheckClass('adult', 'paymentApps');
        return className;
    }

    public String getPdfAdultUtilityBillsMark() {
        String mark = getPdfDocumentMark('adult', 'utilityBills');
        return mark;
    }

    public String getPdfAdultUtilityBillsClass() {
        String className = getPdfDocumentCheckClass('adult', 'utilityBills');
        return className;
    }

    public String getPdfAdultFinancialAssessmentMark() {
        String mark = getPdfDocumentMark('adult', 'financialAssessment');
        return mark;
    }

    public String getPdfAdultFinancialAssessmentClass() {
        String className = getPdfDocumentCheckClass('adult', 'financialAssessment');
        return className;
    }

    public String getPdfHomeWeatherizationYesMark() {
        String mark = '';
        if (pdfHomeEverReceivedWeatherization == 'Yes') {
            mark = getPdfCheckedMark();
        }
        return mark;
    }

    public String getPdfHomeWeatherizationYesClass() {
        String className = '';
        if (pdfHomeEverReceivedWeatherization == 'Yes') {
            className = 'pdf-check-checked';
        }
        return className;
    }

    public String getPdfHomeWeatherizationNoMark() {
        String mark = '';
        if (pdfHomeEverReceivedWeatherization == 'No') {
            mark = getPdfCheckedMark();
        }
        return mark;
    }

    public String getPdfHomeWeatherizationNoClass() {
        String className = '';
        if (pdfHomeEverReceivedWeatherization == 'No') {
            className = 'pdf-check-checked';
        }
        return className;
    }

    private void initializePdfSignatureData(Map<String, String> params) {
        vfApplicantSignatureUrl = params.get('applicantSignatureUrl');
        vfCoApplicantSignatureUrl = params.get('coApplicantSignatureUrl');
        vfApplicantPrintName = params.get('applicantPrintName');
        vfCoApplicantPrintName = params.get('coApplicantPrintName');
        vfApplicantSignDate = formatDateText(params.get('applicantSignDate'));
        vfCoApplicantSignDate = formatDateText(params.get('coApplicantSignDate'));

        if (isPdfRequest() && String.isNotBlank(recordId)) {
            applyStoredSignatureData();
            if (String.isBlank(vfApplicantSignatureUrl)) {
                applyLatestSignatureData(
                    'HIP Application - Applicant Signature%',
                    'HIP Application - Applicant Signature',
                    true
                );
            }
            if (String.isBlank(vfCoApplicantSignatureUrl)) {
                applyLatestSignatureData(
                    'HIP Application - Co-Applicant Signature%',
                    'HIP Application - Co-Applicant Signature',
                    false
                );
            }
        }
    }

    private Boolean isPdfRequest() {
        String pageUrl = ApexPages.currentPage() != null ? ApexPages.currentPage().getUrl() : '';
        return pageUrl != null && pageUrl.toLowerCase().contains('hipapplicationaspdf');
    }

    private void applyStoredSignatureData() {
        try {
            List<Account> accounts = [
                SELECT HIP_Applicant_Sign_Id__c,
                    HIP_Co_Applicant_Sign_Id__c,
                    HIP_Submitted_Date__c
                FROM Account
                WHERE Id = :recordId
                LIMIT 1
            ];

            if (!accounts.isEmpty()) {
                Account accountRecord = accounts[0];
                applyStoredSignature(
                    (String) accountRecord.HIP_Applicant_Sign_Id__c,
                    'HIP Application - Applicant Signature',
                    accountRecord.HIP_Submitted_Date__c,
                    true
                );
                applyStoredSignature(
                    (String) accountRecord.HIP_Co_Applicant_Sign_Id__c,
                    'HIP Application - Co-Applicant Signature',
                    accountRecord.HIP_Submitted_Date__c,
                    false
                );
            }
        } catch (Exception e) {
            // Keep the PDF printable even when signature metadata is not available.
        }
    }

    private void applyStoredSignature(String signatureId, String titlePrefix, Date submittedDate, Boolean isApplicant) {
        String versionId = resolveContentVersionId(signatureId);
        if (String.isNotBlank(versionId)) {
            Id resolvedVersionId = Id.valueOf(versionId);
            List<ContentVersion> versions = [
                SELECT Id, Title
                FROM ContentVersion
                WHERE Id = :resolvedVersionId
                LIMIT 1
            ];

            if (!versions.isEmpty()) {
                ContentVersion versionRecord = versions[0];
                String signatureUrl = buildVersionDownloadUrl(versionRecord.Id);
                Map<String, String> titleData = parseSignatureTitle(versionRecord.Title, titlePrefix);
                String submittedDateText = formatDisplayDate(submittedDate);

                if (isApplicant) {
                    if (String.isBlank(vfApplicantSignatureUrl)) {
                        vfApplicantSignatureUrl = signatureUrl;
                    }
                    if (String.isBlank(vfApplicantPrintName)) {
                        vfApplicantPrintName = titleData.get('printName');
                    }
                    if (String.isBlank(vfApplicantSignDate)) {
                        vfApplicantSignDate = String.isBlank(titleData.get('signDate'))
                            ? submittedDateText
                            : formatDateText(titleData.get('signDate'));
                    }
                } else {
                    if (String.isBlank(vfCoApplicantSignatureUrl)) {
                        vfCoApplicantSignatureUrl = signatureUrl;
                    }
                    if (String.isBlank(vfCoApplicantPrintName)) {
                        vfCoApplicantPrintName = titleData.get('printName');
                    }
                    if (String.isBlank(vfCoApplicantSignDate)) {
                        vfCoApplicantSignDate = String.isBlank(titleData.get('signDate'))
                            ? submittedDateText
                            : formatDateText(titleData.get('signDate'));
                    }
                }
            }
        }
    }

    private void applyLatestSignatureData(String titleLike, String titlePrefix, Boolean isApplicant) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Title,
                ContentDocument.LatestPublishedVersionId,
                ContentDocument.LastModifiedDate
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
            AND ContentDocument.Title LIKE :titleLike
            ORDER BY ContentDocument.LastModifiedDate DESC
            LIMIT 1
        ];

        if (!links.isEmpty()) {
            ContentDocument documentRecord = links[0].ContentDocument;
            String signatureUrl = buildVersionDownloadUrl(documentRecord.LatestPublishedVersionId);
            Map<String, String> titleData = parseSignatureTitle(documentRecord.Title, titlePrefix);

            if (isApplicant) {
                if (String.isBlank(vfApplicantSignatureUrl)) {
                    vfApplicantSignatureUrl = signatureUrl;
                }
                if (String.isBlank(vfApplicantPrintName)) {
                    vfApplicantPrintName = titleData.get('printName');
                }
                if (String.isBlank(vfApplicantSignDate)) {
                    vfApplicantSignDate = formatDateText(titleData.get('signDate'));
                }
            } else {
                if (String.isBlank(vfCoApplicantSignatureUrl)) {
                    vfCoApplicantSignatureUrl = signatureUrl;
                }
                if (String.isBlank(vfCoApplicantPrintName)) {
                    vfCoApplicantPrintName = titleData.get('printName');
                }
                if (String.isBlank(vfCoApplicantSignDate)) {
                    vfCoApplicantSignDate = formatDateText(titleData.get('signDate'));
                }
            }
        }
    }

    private static Map<String, String> parseSignatureTitle(String title, String titlePrefix) {
        Map<String, String> titleData = new Map<String, String>();
        titleData.put('printName', '');
        titleData.put('signDate', '');

        if (String.isBlank(title) || String.isBlank(titlePrefix) || !title.startsWith(titlePrefix)) {
            return titleData;
        }

        String remainingTitle = title.substring(titlePrefix.length()).trim();
        if (remainingTitle.startsWith('-')) {
            remainingTitle = remainingTitle.substring(1).trim();
        }

        Integer dateSeparatorIndex = remainingTitle.lastIndexOf(' - ');
        if (dateSeparatorIndex >= 0) {
            titleData.put('printName', remainingTitle.substring(0, dateSeparatorIndex).trim());
            titleData.put('signDate', remainingTitle.substring(dateSeparatorIndex + 3).trim());
        } else {
            titleData.put('printName', remainingTitle);
        }

        return titleData;
    }

    private static String resolveContentVersionId(String idValue) {
        String candidate = stringValue(idValue);
        if (String.isBlank(candidate) || !isValidIdFormat(candidate)) {
            return '';
        }

        Id contentId = Id.valueOf(candidate);
        if (candidate.startsWith('068')) {
            List<ContentVersion> versions = [
                SELECT Id
                FROM ContentVersion
                WHERE Id = :contentId
                LIMIT 1
            ];
            if (!versions.isEmpty()) {
                return String.valueOf(versions[0].Id);
            }
        } else if (candidate.startsWith('069')) {
            List<ContentVersion> versions = [
                SELECT Id
                FROM ContentVersion
                WHERE ContentDocumentId = :contentId
                AND IsLatest = true
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!versions.isEmpty()) {
                return String.valueOf(versions[0].Id);
            }
        }

        return '';
    }

    private static Map<String, String> getStoredSignatureDisplayData(String signatureId, String titlePrefix, Date submittedDate) {
        Map<String, String> signatureData = new Map<String, String>();
        signatureData.put('signatureUrl', '');
        signatureData.put('printName', '');
        signatureData.put('signDate', '');

        String versionId = resolveContentVersionId(signatureId);
        if (String.isNotBlank(versionId)) {
            Id resolvedVersionId = Id.valueOf(versionId);
            List<ContentVersion> versions = [
                SELECT Id, Title
                FROM ContentVersion
                WHERE Id = :resolvedVersionId
                LIMIT 1
            ];

            if (!versions.isEmpty()) {
                Map<String, String> titleData = parseSignatureTitle(versions[0].Title, titlePrefix);
                signatureData.put('signatureUrl', getOrCreateDistributionUrl(versions[0].Id));
                signatureData.put('printName', titleData.get('printName'));
                signatureData.put(
                    'signDate',
                    String.isBlank(titleData.get('signDate'))
                        ? formatDateForInput(submittedDate)
                        : titleData.get('signDate')
                );
            }
        }

        return signatureData;
    }

    private static Boolean isValidIdFormat(String idValue) {
        String candidate = stringValue(idValue);
        return String.isNotBlank(candidate)
            && (candidate.length() == 15 || candidate.length() == 18)
            && candidate.replaceAll('[A-Za-z0-9]', '').length() == 0;
    }

    private static Map<Id, String> getOrCreateDistributionUrls(Set<Id> contentVersionIds) {
        Map<Id, String> urlsByVersionId = new Map<Id, String>();
        if (contentVersionIds == null || contentVersionIds.isEmpty()) {
            return urlsByVersionId;
        }

        for (ContentDistribution existingDistribution : [
            SELECT ContentVersionId, ContentDownloadUrl
            FROM ContentDistribution
            WHERE ContentVersionId IN :contentVersionIds
            ORDER BY CreatedDate DESC
        ]) {
            if (!urlsByVersionId.containsKey(existingDistribution.ContentVersionId)
                && String.isNotBlank(existingDistribution.ContentDownloadUrl)) {
                urlsByVersionId.put(existingDistribution.ContentVersionId, existingDistribution.ContentDownloadUrl);
            }
        }

        List<ContentDistribution> distributionsToInsert = new List<ContentDistribution>();
        for (Id contentVersionId : contentVersionIds) {
            if (!urlsByVersionId.containsKey(contentVersionId)) {
                ContentDistribution distributionRecord = new ContentDistribution();
                distributionRecord.Name = 'HIP Application File';
                distributionRecord.ContentVersionId = contentVersionId;
                distributionRecord.PreferencesAllowOriginalDownload = true;
                distributionRecord.PreferencesAllowViewInBrowser = true;
                distributionRecord.PreferencesNotifyOnVisit = false;
                distributionsToInsert.add(distributionRecord);
            }
        }

        if (!distributionsToInsert.isEmpty()) {
            insert distributionsToInsert;
            Set<Id> insertedDistributionIds = new Set<Id>();
            for (ContentDistribution distributionRecord : distributionsToInsert) {
                insertedDistributionIds.add(distributionRecord.Id);
            }

            for (ContentDistribution insertedDistribution : [
                SELECT ContentVersionId, ContentDownloadUrl
                FROM ContentDistribution
                WHERE Id IN :insertedDistributionIds
            ]) {
                if (String.isNotBlank(insertedDistribution.ContentDownloadUrl)) {
                    urlsByVersionId.put(insertedDistribution.ContentVersionId, insertedDistribution.ContentDownloadUrl);
                }
            }
        }

        return urlsByVersionId;
    }

    private static String getOrCreateDistributionUrl(Id contentVersionId) {
        if (contentVersionId == null) {
            return '';
        }

        List<ContentDistribution> existingDistributions = [
            SELECT ContentDownloadUrl
            FROM ContentDistribution
            WHERE ContentVersionId = :contentVersionId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!existingDistributions.isEmpty()) {
            return existingDistributions[0].ContentDownloadUrl;
        }

        ContentDistribution distributionRecord = new ContentDistribution();
        distributionRecord.Name = 'HIP Application Signature';
        distributionRecord.ContentVersionId = contentVersionId;
        distributionRecord.PreferencesAllowOriginalDownload = true;
        distributionRecord.PreferencesAllowViewInBrowser = true;
        distributionRecord.PreferencesNotifyOnVisit = false;
        insert distributionRecord;

        distributionRecord = [
            SELECT ContentDownloadUrl
            FROM ContentDistribution
            WHERE Id = :distributionRecord.Id
            LIMIT 1
        ];

        return distributionRecord.ContentDownloadUrl;
    }

    private static String formatDateText(String value) {
        String textValue = stringValue(value);
        if (String.isBlank(textValue)) {
            return '';
        }

        try {
            return formatDisplayDate(Date.valueOf(textValue));
        } catch (Exception e) {
            return textValue;
        }
    }

    private static String formatDateForInput(Date dateValue) {
        return dateValue == null ? '' : String.valueOf(dateValue);
    }

    private static String formatDisplayDate(Date dateValue) {
        if (dateValue == null) {
            return '';
        }

        return String.valueOf(dateValue.month()).leftPad(2, '0')
            + '/'
            + String.valueOf(dateValue.day()).leftPad(2, '0')
            + '/'
            + String.valueOf(dateValue.year());
    }

    private static Boolean hasBorrowerData(Map<String, Object> borrowerPayload) {
        for (String key : borrowerPayload.keySet()) {
            if (String.isNotBlank(stringValue(borrowerPayload.get(key)))) {
                return true;
            }
        }
        return false;
    }

    public class PdfBorrowerData {
        public String roleLabel { get; set; }
        public String name { get; set; }
        public String dateOfBirth { get; set; }
        public String emailAddress { get; set; }
        public String relationship { get; set; }
        public String employer { get; set; }
        public String positionHeld { get; set; }
        public String howLongEmployed { get; set; }
        public String employmentGrossMonthlyAmount { get; set; }
        public String pension { get; set; }
        public String socialSecurityDisability { get; set; }
        public String unemployment { get; set; }
        public String selfEmployment { get; set; }
        public String rentalIncome { get; set; }
        public String alimonyChildSupport { get; set; }
        public String investmentIncome { get; set; }
        public String interestIncome { get; set; }
        public String publicAssistance { get; set; }
        public String otherIncome { get; set; }
        public List<PdfAssetData> assets { get; set; }
    }

    public class PdfAssetData {
        public String accountType { get; set; }
        public String accountNumber { get; set; }
        public String interestRate { get; set; }
        public String institutionName { get; set; }
        public String amount { get; set; }
    }

    public class PdfFinancialData {
        public String salaryWages { get; set; }
        public String otherHouseholdSalary { get; set; }
        public String dividends { get; set; }
        public String bankAndInvestmentInterest { get; set; }
        public String investments { get; set; }
        public String reimbursements { get; set; }
        public String otherIncome { get; set; }
        public String totalMonthlyIncome { get; set; }
        public String housingMortgageTaxesInsurance { get; set; }
        public String carLoan { get; set; }
        public String carInsurance { get; set; }
        public String houseInsurance { get; set; }
        public String lifeInsurance { get; set; }
        public String childcare { get; set; }
        public String charity { get; set; }
        public String gasElectric { get; set; }
        public String telephone { get; set; }
        public String cableSatelliteTv { get; set; }
        public String internet { get; set; }
        public String food { get; set; }
        public String entertainment { get; set; }
        public String gifts { get; set; }
        public String clothing { get; set; }
        public String petSupplies { get; set; }
        public String healthInsurance { get; set; }
        public String otherExpense { get; set; }
        public String alimonyChildSupport { get; set; }
        public String totalLivingExpenses { get; set; }
        public String difference { get; set; }
    }

}