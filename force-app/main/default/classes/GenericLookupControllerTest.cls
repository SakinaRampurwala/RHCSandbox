@IsTest
public class GenericLookupControllerTest {

    @TestSetup
    static void setupData() {
        List<Account> accs = new List<Account>();
        for(Integer i=0;i<6;i++){
            accs.add(new Account(Name='Test Acc '+i));
        }
        insert accs;
    }

    @IsTest
    static void test1() {

        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();

        GenericLookupController.retriveSearchData('Account', 'Id,Name', 'Name', 'Test', 'Name != null', new List<String>{acc.Id});

        GenericLookupController.retriveSearchData('Account', 'Id,Name', 'Name', '', '', null);

        Test.stopTest();
    }

    @IsTest
    static void test2() {

        List<Account> accs = [SELECT Id FROM Account LIMIT 2];

        Test.startTest();

        GenericLookupController.retrieveRecordsByIds('Account', 'Id,Name', new List<String>{accs[0].Id, accs[1].Id});

        GenericLookupController.retrieveRecordsByIds('', 'Id', new List<String>{accs[0].Id});

        GenericLookupController.retrieveRecordsByIds('Account', 'Id', new List<String>());

        GenericLookupController.retrieveRecordsByIds('Account', 'Id', new List<String>{'INVALIDID123'});

        Test.stopTest();
    }
}