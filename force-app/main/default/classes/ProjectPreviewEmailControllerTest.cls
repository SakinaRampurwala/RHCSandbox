@IsTest
public class ProjectPreviewEmailControllerTest {

    @TestSetup
    static void setupData() {

        Account acc = new Account(Name='Test');
        insert acc;

        Contact c = new Contact(LastName='Test', Email='test@test.com', AccountId=acc.Id);
        insert c;

        ContentVersion cv = new ContentVersion(Title='File', PathOnClient='file.txt', VersionData=Blob.valueOf('Test'));
        insert cv;

        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        insert new ContentDocumentLink(ContentDocumentId = docId, LinkedEntityId = acc.Id, ShareType='V');

        User u = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        System.runAs(u){
            EmailTemplate et = new EmailTemplate(Name='Template', DeveloperName='Annual_Certification', FolderId=UserInfo.getUserId(), TemplateType='text', Subject='Test Subject', Body='Hello {!URL} {!$Organization.Name}');
            insert et;
        }
    }

    @IsTest
    static void test1() {

        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();

        ProjectPreviewEmailController.getEmailSignature();
        ProjectPreviewEmailController.getOrgWideEmailAddresses();
        ProjectPreviewEmailController.getRelatedFiles(acc.Id);

        Test.stopTest();
    }

    @IsTest
    static void test2() {

        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();

        ProjectPreviewEmailController.getEmailBody(acc.Id, 'AnnualCertification');

        ProjectPreviewEmailController.getEmailBody(acc.Id, 'InvalidTemplate');

        ProjectPreviewEmailController.getEmailBody(acc.Id, null);

        Test.stopTest();
    }

    @IsTest
    static void test3() {

        Account acc = [SELECT Id FROM Account LIMIT 1];

        ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion LIMIT 1];

        ProjectPreviewEmailController.DataWrap wrap = new ProjectPreviewEmailController.DataWrap();
        wrap.recordId = acc.Id;
        wrap.includeRefId = true;
        wrap.toEmails = new List<String>{'test@test.com'};
        wrap.subject = 'Test';
        wrap.htmlBody = 'Body';
        wrap.useEmailSignature = true;
        wrap.saveAsActivity = false;
        wrap.fileIds = new List<String>{cv.ContentDocumentId};

        String jsonData = JSON.serialize(wrap);

        Test.startTest();

        ProjectPreviewEmailController.sendEmail(jsonData);

        ProjectPreviewEmailController.sendEmail('{}');

        String base64 = EncodingUtil.base64Encode(Blob.valueOf('Sign'));
        ProjectPreviewEmailController.saveSignature(acc.Id, base64);

        ProjectPreviewEmailController.saveSignature(acc.Id, '');

        Test.stopTest();
    }
}