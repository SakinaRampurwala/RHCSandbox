@IsTest
private class NoticeToProceedCtrlTest {

    @TestSetup
    static void setupData() {
        Account customer = new Account(Name = 'Test Customer');
        insert customer;

        Account contractor = new Account(
            Name = 'Test Contractor',
            Phone = '555-1212',
            BillingStreet = '100 Main St',
            BillingCity = 'Albany',
            BillingState = 'NY',
            BillingPostalCode = '12207',
            BillingCountry = 'USA'
        );
        insert contractor;

        insert buildProject(customer.Id, contractor.Id);
    }

    @IsTest
    static void testGetNoticeDataAndInitPdf() {
        Id projectId = [SELECT Id FROM buildertek__Project__c LIMIT 1].Id;

        Test.startTest();
        NoticeToProceedCtrl.NoticeData data = NoticeToProceedCtrl.getNoticeData(projectId);
        NoticeToProceedCtrl.NoticeData emptyData = NoticeToProceedCtrl.getNoticeData(null);
        Test.stopTest();

        System.assertNotEquals(null, data, 'Notice data should be returned.');
        System.assertNotEquals(null, emptyData, 'Null record should return empty wrapper.');

        Test.setCurrentPage(Page.NoticeToProceedAsPDF);
        ApexPages.currentPage().getParameters().put('recordId', String.valueOf(projectId));
        ApexPages.currentPage().getParameters().put('imgUrl', 'https://example.com/sign.png');
        ApexPages.currentPage().getParameters().put('signerName', 'Signer Name');

        NoticeToProceedCtrl controller = new NoticeToProceedCtrl();
        controller.initPdf();

        System.assertNotEquals(null, controller.vfNoticeData, 'VF notice data should initialize.');
        System.assertEquals('https://example.com/sign.png', controller.vfImgUrl);
        System.assertEquals('Signer Name', controller.vfSignerName);
        System.assertNotEquals(null, controller.currentRecordDate, 'Date should be set for PDF.');
    }

    @IsTest
    static void testSaveSignatureAndSavePdf() {
        Id projectId = [SELECT Id FROM buildertek__Project__c LIMIT 1].Id;

        String signatureBody = EncodingUtil.base64Encode(Blob.valueOf('fake-signature'));

        Test.startTest();
        Map<String, String> signatureResult = NoticeToProceedCtrl.saveSignature(projectId, signatureBody);
        String pdfResult = NoticeToProceedCtrl.savePdf(
            projectId,
            UserInfo.getUserId(),
            Date.today().format(),
            signatureResult.get('imgUrl'),
            'Signer Name',
            signatureResult.get('cvId')
        );
        Test.stopTest();

        System.assertEquals('Success', pdfResult, 'PDF save should succeed.');
        System.assertEquals(true, String.isNotBlank(signatureResult.get('cvId')));

        buildertek__Project__c savedProject = [
            SELECT Notice_To_Proceed_Submitted__c, Notice_To_Proceed_Submitted_Date__c
            FROM buildertek__Project__c
            WHERE Id = :projectId
        ];
        System.assertEquals(true, savedProject.Notice_To_Proceed_Submitted__c, 'Submitted flag should be set.');
        System.assertEquals(Date.today(), savedProject.Notice_To_Proceed_Submitted_Date__c, 'Submitted date should be set.');

        List<ContentVersion> pdfFiles = [
            SELECT Id, Title
            FROM ContentVersion
            WHERE Title LIKE 'Notice To Proceed%'
        ];
        System.assert(!pdfFiles.isEmpty(), 'PDF content should be created.');

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :projectId
        ];
        System.assert(!links.isEmpty(), 'PDF should be linked to project.');
    }

    private static buildertek__Project__c buildProject(Id customerId, Id contractorId) {
        Schema.SObjectType projectType = Schema.getGlobalDescribe().get('buildertek__Project__c');
        buildertek__Project__c project = (buildertek__Project__c) projectType.newSObject();
        Map<String, Schema.SObjectField> fields = projectType.getDescribe().fields.getMap();

        putIfExists(project, fields, 'Name', 'Test Project');
        putIfExists(project, fields, 'buildertek__Address__c', '123 Test St');
        putIfExists(project, fields, 'buildertek__City_Text__c', 'Albany');
        putIfExists(project, fields, 'buildertek__State__c', 'NY');
        putIfExists(project, fields, 'buildertek__Zip__c', '12207');
        putIfExists(project, fields, 'buildertek__Country__c', 'USA');

        putIfExists(project, fields, 'Case_No__c', 'CASE-1001');
        putIfExists(project, fields, 'buildertek__Case_No__c', 'CASE-1001');

        putIfExists(project, fields, 'buildertek__Project_Start_Date__c', Date.today().addDays(7));
        putIfExists(project, fields, 'buildertek__Project_Completion_Date__c', Date.today().addDays(30));
        putIfExists(project, fields, 'buildertek__Contract_Date__c', Date.today());

        putIfExists(project, fields, 'buildertek__Customer__c', customerId);
        putIfExists(project, fields, 'General_Contractor__c', contractorId);
        putIfExists(project, fields, 'buildertek__General_Contractor__c', contractorId);

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
