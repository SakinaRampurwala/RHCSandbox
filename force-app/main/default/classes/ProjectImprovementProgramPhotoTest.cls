@IsTest
public class ProjectImprovementProgramPhotoTest {

    @TestSetup
    static void setupData() {
        Account customer = new Account(Name = 'Photo Customer');
        insert customer;

        insert buildProject(customer.Id);
    }

    @IsTest
    static void testReadMethodsAndInitPdf() {
        Id projectId = [SELECT Id FROM buildertek__Project__c LIMIT 1].Id;
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        Organization orgInfo = ProjectImprovementProgramPhotoCtrl.getOrgInfo();
        String logoUrl = ProjectImprovementProgramPhotoCtrl.getLogoUrl();
        ProjectImprovementProgramPhotoCtrl.SenderInfo sender = ProjectImprovementProgramPhotoCtrl.getSenderInfo(currentUserId);
        ProjectImprovementProgramPhotoCtrl.SenderInfo noSender = ProjectImprovementProgramPhotoCtrl.getSenderInfo(null);
        List<String> attestation = ProjectImprovementProgramPhotoCtrl.getAttestationItems();
        ProjectImprovementProgramPhotoCtrl.ApplicationStatusWrapper appStatus = ProjectImprovementProgramPhotoCtrl.getApplicationStatus(projectId);
        ProjectImprovementProgramPhotoCtrl.ApplicationStatusWrapper noStatus = ProjectImprovementProgramPhotoCtrl.getApplicationStatus(null);
        Test.stopTest();

        System.assertNotEquals(null, orgInfo, 'Organization should be returned.');
        System.assertNotEquals(null, attestation, 'Attestation list should be returned.');
        System.assert(!attestation.isEmpty(), 'Attestation list should not be empty.');
        System.assertNotEquals(null, appStatus, 'Application status should be returned for valid record.');
        System.assertEquals(false, appStatus.isSubmitted, 'Initial project should not be submitted.');
        System.assertEquals('', appStatus.primarySignatureUrl, 'No primary signature URL should exist initially.');
        System.assertEquals('', appStatus.secondarySignatureUrl, 'No secondary signature URL should exist initially.');
        System.assertEquals(null, noStatus, 'Null record should return null application status.');
        System.assertEquals(null, noSender, 'Null sender should return null sender info.');
        System.assertEquals(true, sender != null, 'Current user sender info should be returned.');

        Test.setCurrentPage(Page.ProjectImprovementProgramAsPDF);
        ApexPages.currentPage().getParameters().put('recordId', String.valueOf(projectId));
        ApexPages.currentPage().getParameters().put('senderId', String.valueOf(currentUserId));
        ApexPages.currentPage().getParameters().put('sendDate', Date.today().format());
        ApexPages.currentPage().getParameters().put('imgUrl', 'https://example.com/primary-sign.png');
        ApexPages.currentPage().getParameters().put('signerName', 'Primary Signer');
        ApexPages.currentPage().getParameters().put('coSignerImgUrl', 'https://example.com/secondary-sign.png');
        ApexPages.currentPage().getParameters().put('coSignerName', 'Co Signer');

        ProjectImprovementProgramPhotoCtrl controller = new ProjectImprovementProgramPhotoCtrl();
        controller.initPdf();

        System.assertNotEquals(null, controller.attestationList, 'Init should load attestation list.');
        System.assertEquals('Primary Signer', controller.vfSignerName);
        System.assertEquals('Co Signer', controller.vfCoSignerName);
        System.assertNotEquals(null, controller.vfProjectAddress, 'Project address should be loaded.');
        System.assertNotEquals(null, controller.currentRecordDate, 'Current date should be loaded.');

        System.assertEquals(true, logoUrl == null || logoUrl.contains('/servlet/servlet.FileDownload?file='));
    }

    @IsTest
    static void testSaveSignatureAndSavePdfAndSaveAttestation() {
        Id projectId = [SELECT Id FROM buildertek__Project__c LIMIT 1].Id;
        String signatureBody = EncodingUtil.base64Encode(Blob.valueOf('primary-signature'));
        String coSignatureBody = EncodingUtil.base64Encode(Blob.valueOf('co-signature'));

        Test.startTest();
        Map<String, String> primarySig = ProjectImprovementProgramPhotoCtrl.saveSignature(projectId, signatureBody, 'Home Owner 1');
        Map<String, String> secondarySig = ProjectImprovementProgramPhotoCtrl.saveSignature(projectId, coSignatureBody, 'Home Owner 2');

        String savePdfResult = ProjectImprovementProgramPhotoCtrl.savePdf(
            projectId,
            UserInfo.getUserId(),
            Date.today().format(),
            primarySig.get('imgUrl'),
            'Primary Signer',
            primarySig.get('cvId'),
            secondarySig.get('imgUrl'),
            'Co Signer',
            secondarySig.get('cvId')
        );

        String legacyResult = ProjectImprovementProgramPhotoCtrl.saveAttestation(
            String.valueOf(projectId),
            signatureBody,
            new List<String>{'Sample Item'},
            String.valueOf(UserInfo.getUserId()),
            Date.today().format()
        );
        Test.stopTest();

        System.assertEquals('Success', savePdfResult, 'savePdf should return success.');
        System.assert(String.isNotBlank(primarySig.get('cvId')), 'Primary signature file should be created.');
        System.assert(String.isNotBlank(secondarySig.get('cvId')), 'Secondary signature file should be created.');
        System.assert(legacyResult.contains('Signature saved'), 'Legacy wrapper should return guidance message.');

        Map<String, Schema.SObjectField> projectFields = buildertek__Project__c.SObjectType.getDescribe().fields.getMap();
        List<String> queryFields = new List<String>{ 'Id', 'Home_Improvement_Submitted_Date__c' };
        if (projectFields.containsKey('Home_Improve_Photo_Primary_Sign_Id__c')) {
            queryFields.add('Home_Improve_Photo_Primary_Sign_Id__c');
        }
        if (projectFields.containsKey('Home_Improve_Photo_Secondary_Sign_Id__c')) {
            queryFields.add('Home_Improve_Photo_Secondary_Sign_Id__c');
        }
        if (projectFields.containsKey('Home_Improve_Photo_Primary_Name__c')) {
            queryFields.add('Home_Improve_Photo_Primary_Name__c');
        }
        if (projectFields.containsKey('Home_Improve_Photo_Secondary_Name__c')) {
            queryFields.add('Home_Improve_Photo_Secondary_Name__c');
        }

        SObject savedProject = Database.query(
            'SELECT ' + String.join(queryFields, ',') + ' FROM buildertek__Project__c WHERE Id = :projectId LIMIT 1'
        );

        System.assertEquals(Date.today(), savedProject.get('Home_Improvement_Submitted_Date__c'), 'Submitted date should be set.');
        if (projectFields.containsKey('Home_Improve_Photo_Primary_Sign_Id__c')) {
            System.assertEquals(primarySig.get('cvId'), savedProject.get('Home_Improve_Photo_Primary_Sign_Id__c'));
        }
        if (projectFields.containsKey('Home_Improve_Photo_Secondary_Sign_Id__c')) {
            System.assertEquals(secondarySig.get('cvId'), savedProject.get('Home_Improve_Photo_Secondary_Sign_Id__c'));
        }
        if (projectFields.containsKey('Home_Improve_Photo_Primary_Name__c')) {
            System.assertEquals('Primary Signer', savedProject.get('Home_Improve_Photo_Primary_Name__c'));
        }
        if (projectFields.containsKey('Home_Improve_Photo_Secondary_Name__c')) {
            System.assertEquals('Co Signer', savedProject.get('Home_Improve_Photo_Secondary_Name__c'));
        }

        ProjectImprovementProgramPhotoCtrl.ApplicationStatusWrapper submittedStatus =
            ProjectImprovementProgramPhotoCtrl.getApplicationStatus(projectId);

        System.assertEquals(true, submittedStatus.isSubmitted, 'Submitted status should be returned after save.');
        System.assertEquals('Primary Signer', submittedStatus.signerName, 'Primary signer name should be returned from record state.');
        System.assertEquals('Co Signer', submittedStatus.coSignerName, 'Secondary signer name should be returned from record state.');
        System.assert(String.isNotBlank(submittedStatus.primarySignatureUrl), 'Primary signature URL should be returned after save.');
        System.assert(String.isNotBlank(submittedStatus.secondarySignatureUrl), 'Secondary signature URL should be returned after save.');

        String duplicateSubmitResult = ProjectImprovementProgramPhotoCtrl.savePdf(
            projectId,
            UserInfo.getUserId(),
            Date.today().format(),
            primarySig.get('imgUrl'),
            'Primary Signer',
            primarySig.get('cvId'),
            secondarySig.get('imgUrl'),
            'Co Signer',
            secondarySig.get('cvId')
        );

        System.assertEquals('Already Submitted', duplicateSubmitResult, 'Duplicate submit should be blocked.');

        List<ContentVersion> pdfFiles = [
            SELECT Id, Title
            FROM ContentVersion
            WHERE Title LIKE 'Home Improvement%'
        ];
        System.assert(!pdfFiles.isEmpty(), 'PDF file should be created.');

        List<ContentDocumentLink> links = [
            SELECT Id, ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :projectId
        ];
        System.assert(!links.isEmpty(), 'Files should be linked to the project record.');

        Integer signatureLinkCount = 0;
        Integer pdfLinkCount = 0;
        for (ContentDocumentLink linkRecord : links) {
            if (linkRecord.ContentDocument.Title == 'Home Improvement Program Photo Release Home Owner 1 Signature' ||
                linkRecord.ContentDocument.Title == 'Home Improvement Program Photo Release Home Owner 2 Signature') {
                signatureLinkCount++;
            }
            if (linkRecord.ContentDocument.Title != null &&
                linkRecord.ContentDocument.Title.endsWith('.pdf')) {
                pdfLinkCount++;
            }
        }

        System.assert(signatureLinkCount >= 2, 'Both submitted signature files should be linked to the project record.');
        System.assertEquals(1, pdfLinkCount, 'Generated PDF should be linked to the project record.');

        Test.setCurrentPage(Page.ProjectImprovementProgramAsPDF);
        ApexPages.currentPage().getParameters().put('recordId', String.valueOf(projectId));
        ApexPages.currentPage().getParameters().put('senderId', String.valueOf(UserInfo.getUserId()));
        ApexPages.currentPage().getParameters().put('sendDate', Date.today().format());

        ProjectImprovementProgramPhotoCtrl controller = new ProjectImprovementProgramPhotoCtrl();
        controller.initPdf();

        System.assertEquals('Primary Signer', controller.vfSignerName, 'PDF controller should load saved primary signer name.');
        System.assertEquals('Co Signer', controller.vfCoSignerName, 'PDF controller should load saved secondary signer name.');
        System.assert(String.isNotBlank(controller.vfImgUrl), 'PDF controller should load saved primary signature URL.');
        System.assert(String.isNotBlank(controller.vfCoSignerImgUrl), 'PDF controller should load saved secondary signature URL.');

        Test.setCurrentPage(Page.ProjectImprovementProgramAsPDF);
        ApexPages.currentPage().getParameters().put('Id', String.valueOf(projectId));

        ProjectImprovementProgramPhotoCtrl directPageController = new ProjectImprovementProgramPhotoCtrl();
        directPageController.initPdf();

        System.assertEquals('Primary Signer', directPageController.vfSignerName, 'VF page should load stored primary signer name when only Id is provided.');
        System.assertEquals('Co Signer', directPageController.vfCoSignerName, 'VF page should load stored secondary signer name when only Id is provided.');
        System.assertEquals('Photo Customer', directPageController.vfCustomerName, 'VF page should load customer name from the project.');
        System.assertEquals('10 River Rd, Rochester, NY 14604, USA', directPageController.vfProjectAddress, 'VF page should format the address consistently.');
        System.assert(String.isNotBlank(directPageController.vfImgUrl), 'VF page should load stored primary signature image when params are missing.');
        System.assert(String.isNotBlank(directPageController.vfCoSignerImgUrl), 'VF page should load stored secondary signature image when params are missing.');
        System.assertEquals(
            DateTime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0)).format('MM-dd-yyyy'),
            directPageController.currentRecordDate,
            'VF page should fall back to the stored submitted date when sendDate is not provided.'
        );
    }

    public static buildertek__Project__c buildProject(Id customerId) {
        Schema.SObjectType projectType = Schema.getGlobalDescribe().get('buildertek__Project__c');
        buildertek__Project__c project = (buildertek__Project__c) projectType.newSObject();
        Map<String, Schema.SObjectField> fields = projectType.getDescribe().fields.getMap();

        putIfExists(project, fields, 'Name', 'Photo Project');
        putIfExists(project, fields, 'buildertek__Address__c', '10 River Rd');
        putIfExists(project, fields, 'buildertek__City_Text__c', 'Rochester');
        putIfExists(project, fields, 'buildertek__State__c', 'NY');
        putIfExists(project, fields, 'buildertek__Zip__c', '14604');
        putIfExists(project, fields, 'buildertek__Country__c', 'USA');
        putIfExists(project, fields, 'buildertek__Customer__c', customerId);

        applyRequiredDefaults(project, fields);
        return project;
    }

    public static void putIfExists(SObject sobj, Map<String, Schema.SObjectField> fields, String apiName, Object value) {
        if (fields.containsKey(apiName) && value != null) {
            try {
                Schema.DisplayType fieldType = fields.get(apiName).getDescribe().getType();
                if ((fieldType == Schema.DisplayType.Reference || fieldType == Schema.DisplayType.Id) && !(value instanceof Id)) {
                    return;
                }
                sobj.put(apiName, value);
            } catch (Exception e) {
                // Ignore mismatched optional test data assignments.
            }
        }
    }

    public static void applyRequiredDefaults(SObject sobj, Map<String, Schema.SObjectField> fields) {
        Map<String, Object> currentValues = sobj.getPopulatedFieldsAsMap();

        for (String fieldName : fields.keySet()) {
            if (currentValues.containsKey(fieldName)) {
                continue;
            }

            Schema.DescribeFieldResult dfr = fields.get(fieldName).getDescribe();
            if (!dfr.isCreateable() || dfr.isNillable() || dfr.isDefaultedOnCreate() || dfr.isAutoNumber()) {
                continue;
            }

            if (fieldName == 'OwnerId' || fieldName == 'RecordTypeId') {
                continue;
            }

            Schema.DisplayType fieldType = dfr.getType();
            if (fieldType == Schema.DisplayType.String ||
                fieldType == Schema.DisplayType.TextArea ||
                fieldType == Schema.DisplayType.Email ||
                fieldType == Schema.DisplayType.Phone) {
                sobj.put(fieldName, 'Test');
            } else if (fieldType == Schema.DisplayType.Boolean) {
                sobj.put(fieldName, false);
            } else if (fieldType == Schema.DisplayType.Integer) {
                sobj.put(fieldName, 1);
            } else if (fieldType == Schema.DisplayType.Double ||
                       fieldType == Schema.DisplayType.Currency ||
                       fieldType == Schema.DisplayType.Percent) {
                sobj.put(fieldName, 1);
            } else if (fieldType == Schema.DisplayType.Date) {
                sobj.put(fieldName, Date.today());
            } else if (fieldType == Schema.DisplayType.Datetime) {
                sobj.put(fieldName, System.now());
            } else if (fieldType == Schema.DisplayType.Picklist) {
                List<Schema.PicklistEntry> entries = dfr.getPicklistValues();
                if (!entries.isEmpty()) {
                    sobj.put(fieldName, entries[0].getValue());
                }
            }
        }
    }
}