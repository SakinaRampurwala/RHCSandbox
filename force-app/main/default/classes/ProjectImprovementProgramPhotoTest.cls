@IsTest
private class ProjectImprovementProgramPhotoTest {

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
        buildertek__Project__c appStatus = ProjectImprovementProgramPhotoCtrl.getApplicationStatus(projectId);
        buildertek__Project__c noStatus = ProjectImprovementProgramPhotoCtrl.getApplicationStatus(null);
        Test.stopTest();

        System.assertNotEquals(null, orgInfo, 'Organization should be returned.');
        System.assertNotEquals(null, attestation, 'Attestation list should be returned.');
        System.assert(!attestation.isEmpty(), 'Attestation list should not be empty.');
        System.assertNotEquals(null, appStatus, 'Application status should be returned for valid record.');
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
        Map<String, String> primarySig = ProjectImprovementProgramPhotoCtrl.saveSignature(projectId, signatureBody);
        Map<String, String> secondarySig = ProjectImprovementProgramPhotoCtrl.saveSignature(projectId, coSignatureBody);

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

        buildertek__Project__c savedProject = [
            SELECT Home_Improvement_Submitted__c, Home_Improvement_Submitted_Date__c
            FROM buildertek__Project__c
            WHERE Id = :projectId
        ];

        System.assertEquals(true, savedProject.Home_Improvement_Submitted__c, 'Submitted flag should be set.');
        System.assertEquals(Date.today(), savedProject.Home_Improvement_Submitted_Date__c, 'Submitted date should be set.');

        List<ContentVersion> pdfFiles = [
            SELECT Id, Title
            FROM ContentVersion
            WHERE Title LIKE 'Home Improvement%'
        ];
        System.assert(!pdfFiles.isEmpty(), 'PDF file should be created.');

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :projectId
        ];
        System.assert(!links.isEmpty(), 'PDF should be linked to project record.');
    }

    private static buildertek__Project__c buildProject(Id customerId) {
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

    private static void putIfExists(SObject sobj, Map<String, Schema.SObjectField> fields, String apiName, Object value) {
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

    private static void applyRequiredDefaults(SObject sobj, Map<String, Schema.SObjectField> fields) {
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
