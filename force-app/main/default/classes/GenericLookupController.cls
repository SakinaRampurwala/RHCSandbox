public class GenericLookupController {
    
    @AuraEnabled
    public static List<sObject> retriveSearchData(String ObjectName, String fieldNames, String searchField, String searchValue, String searchCondition, List<String> selectedRecId) {
        List<sObject> sObjectResultList = new List<sObject>();
        if(selectedRecId == null) {
            selectedRecId = new List<String>();
        }

        String query = 'Select '+fieldNames+' FROM '+ObjectName+ ' WHERE ';
        if(String.isNotEmpty(searchValue)) {
            query += searchField + ' LIKE \'%' + searchValue.trim() + '%\' AND ';
        }
        if(String.isNotEmpty(searchCondition)) {
            query += searchCondition + ' AND ';
        }
        query += 'Id NOT IN: selectedRecId ';
        query += 'ORDER BY CreatedDate DESC LIMIT 5';

        sObjectResultList = Database.Query(query);

        return sObjectResultList;
    }

    @AuraEnabled
    public static List<sObject> retrieveRecordsByIds(String objectName, String fieldNames, List<String> recordIds) {
        if (String.isBlank(objectName) || String.isBlank(fieldNames) || recordIds == null || recordIds.isEmpty()) {
            return new List<sObject>();
        }

        Set<Id> validIds = new Set<Id>();
        for (String recordId : recordIds) {
            if (String.isBlank(recordId)) {
                continue;
            }
            try {
                validIds.add((Id)recordId);
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'Skipping invalid Id: ' + recordId + ' due to ' + ex.getMessage());
            }
        }

        if (validIds.isEmpty()) {
            return new List<sObject>();
        }

        String query = 'SELECT ' + fieldNames + ' FROM ' + objectName + ' WHERE Id IN :validIds';
        return Database.query(query);
    }
}