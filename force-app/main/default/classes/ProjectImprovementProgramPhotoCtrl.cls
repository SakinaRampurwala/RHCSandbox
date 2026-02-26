public without sharing class ProjectImprovementProgramPhotoCtrl {

    @AuraEnabled(cacheable=true)
    public static Organization getOrgInfo() {
        return [SELECT Id, Name FROM Organization LIMIT 1];
    }
    
    @AuraEnabled(cacheable=true)
    public static String getLogoUrl() {
        try {
            buildertek__ConfirmationSiteURL__c sitesUrl = buildertek__ConfirmationSiteURL__c.getOrgDefaults();
            
            String baseUrl = '';
            if (sitesUrl != null && !String.isBlank(sitesUrl.buildertek__Sites_URL__c)) {
                baseUrl = sitesUrl.buildertek__Sites_URL__c;
            } else {
                // Fallback or relative path
                baseUrl = URL.getOrgDomainUrl().toExternalForm();
            }

            List<Document> logoDocs = [SELECT Id FROM Document WHERE DeveloperName = 'Company_Logo' LIMIT 1];
            if (logoDocs.isEmpty()) {
                logoDocs = [SELECT Id FROM Document WHERE Name = 'BuildettekLogo' LIMIT 1];
            }

            if (logoDocs.isEmpty()) {
                return null;
            }

            String logoUrl = baseUrl + '/servlet/servlet.FileDownload?file=' + logoDocs[0].Id;
            return logoUrl;
        } catch (Exception e) {
            return null;
        }
    }

    public class SenderInfo {
        @AuraEnabled public String organizationName;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String postalCode;
        @AuraEnabled public String name;
        @AuraEnabled public String phone;
        @AuraEnabled public String altPhone;
        @AuraEnabled public String email;
    }

    @AuraEnabled(cacheable=true)
    public static SenderInfo getSenderInfo(Id senderId) {
        if (senderId == null) {
            return null;
        }

        List<User> users = [
            SELECT Id, Name, Email, Phone, MobilePhone, Department, CompanyName,
                   Street, City, State, PostalCode
            FROM User
            WHERE Id = :senderId
            LIMIT 1
        ];

        if (users.isEmpty()) {
            return null;
        }

        User u = users[0];
        SenderInfo info = new SenderInfo();
        info.organizationName = !String.isBlank(u.Department) ? u.Department : u.CompanyName;
        info.street = u.Street;
        info.city = u.City;
        info.state = u.State;
        info.postalCode = u.PostalCode;
        info.name = u.Name;
        info.phone = u.Phone;
        info.altPhone = u.MobilePhone;
        info.email = u.Email;
        return info;
    }

    @AuraEnabled
    public static Map<String, String> saveSignature(Id recordId, String signatureBody) {
        try {
            ContentVersion cv = new ContentVersion();
            cv.Title = 'Home Improvement Signature';
            cv.PathOnClient = 'Signature.png';
            cv.VersionData = EncodingUtil.base64Decode(signatureBody);
            cv.IsMajorVersion = true;
            insert cv;

            ContentDistribution cd = new ContentDistribution();
            cd.Name = 'Home Improvement Signature';
            cd.ContentVersionId = cv.Id;
            cd.PreferencesAllowViewInBrowser = true;
            try {
                insert cd;
                cd = [SELECT ContentDownloadUrl FROM ContentDistribution WHERE Id = :cd.Id];
            } catch (Exception e) {
                // If ContentDistribution fails, we might be in a restricted guest context
                // We'll return null for imgUrl and handle it in savePdf if needed
                Map<String, String> errResult = new Map<String, String>();
                errResult.put('imgUrl', '');
                errResult.put('cvId', cv.Id);
                return errResult;
            }

            Map<String, String> result = new Map<String, String>();
            result.put('imgUrl', cd.ContentDownloadUrl);
            result.put('cvId', cv.Id);
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving signature: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getAttestationItems() {
        return new List<String>{
            'I acknowledge that a lien will be placed on my property for a period of 2, 5, or 10 years. I must reside in the house for that period or pay the grant back.',
            'I understand that any changes to the scope of work are my responsibility to pay for.',
            'I understand that I must promptly reply to any requests for additional or missing documentation or I will be removed from the program.',
            'I agree to provide access to my home for contractors to work from 8am to 5pm, Monday through Friday, for the duration of the contract.',
            'I acknowledge that I may be required to contribute a portion of the project cost based on my income.',
            'I understand that all individuals listed on the deed must sign all necessary paperwork and liens for this project.',
            'I acknowledge that failure to attend scheduled appointments will result in dismissal from the grant program and rescission of funding.',
            'I will provide full access to the entire property to the construction manager, inspectors, contractor, and staff during both the application and construction processes.',
            'I understand that I am responsible for the behavior of myself, residents, visitors, and agents. Aggression, intimidation, or harassment from any of these parties will result in my termination from the program.',
            'All pets must be secured during appointments and construction. Failure to do so will result in removal from the program.',
            'I will maintain my property in a clean, safe, and sanitary condition throughout the application and construction processes, as well as during the regulatory period, or I will be removed from the program.',
            'I acknowledge that not all deficiencies in my property may be addressed, and my home may not be eligible for any repairs due to the type or extent of repairs required.',
            'I agree to take financial literacy training provided by The Housing Council at PathStone prior to final acceptance into the program.',
            'I acknowledge my taxes and mortgage have been paid on time for the last 3 months and will continue to be paid on time during the application and construction process.'
        };
    }

    @AuraEnabled(cacheable=true)
    public static buildertek__Project__c getApplicationStatus(Id recordId) {
        if (recordId == null) return null;
        try {
            return [
                SELECT Id, Home_Improvement_Submitted__c, Home_Improvement_Submitted_Date__c
                FROM buildertek__Project__c
                WHERE Id = :recordId
                LIMIT 1
            ];
        } catch (Exception e) {
            return null;
        }
    }

    @AuraEnabled
    public static String savePdf(
        Id recordId,
        String senderId,
        String sendDate,
        String imgUrl,
        String signerName,
        String signatureId,
        String coSignerImgUrl,
        String coSignerName,
        String coSignatureId
    ) {
        try {
            PageReference pdfPage = Page.ProjectImprovementProgramAsPDF;
            pdfPage.getParameters().put('recordId', recordId);
            pdfPage.getParameters().put('senderId', senderId);
            pdfPage.getParameters().put('sendDate', sendDate);
            pdfPage.getParameters().put('imgUrl', imgUrl);
            pdfPage.getParameters().put('signerName', signerName);
            pdfPage.getParameters().put('coSignerImgUrl', coSignerImgUrl);
            pdfPage.getParameters().put('coSignerName', coSignerName);
            
            Blob pdfBlob;
            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('Test PDF');
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }

            ContentVersion pdfCv = new ContentVersion();
            pdfCv.Title = 'Home Improvement ' + system.now().format('MM-dd-yyyy') + '.pdf';
            pdfCv.PathOnClient = 'HomeImprovement.pdf';
            pdfCv.VersionData = pdfBlob;
            pdfCv.IsMajorVersion = true;
            insert pdfCv;

            Id pdfDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :pdfCv.Id].ContentDocumentId;

            ContentDocumentLink pdfCdl = new ContentDocumentLink();
            pdfCdl.ContentDocumentId = pdfDocId;
            pdfCdl.LinkedEntityId = recordId;
            pdfCdl.ShareType = 'V';
            insert pdfCdl;

            // Update Project fields
            buildertek__Project__c proj = new buildertek__Project__c(Id = recordId);
            proj.Home_Improvement_Submitted__c = true;
            proj.Home_Improvement_Submitted_Date__c = Date.today();
            update proj;

            // Cleanup signature files if they exist
            cleanupSignatureFile(signatureId);
            cleanupSignatureFile(coSignatureId);

            return 'Success';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // Wrapper for backward compatibility (in case LWC JS is cached)
    @AuraEnabled
    public static String saveAttestation(String recordId, String signatureBody, List<String> checkedLabels, String senderId, String sendDate) {
        try {
            // We only save the signature here because calling getContentAsPDF after DML in the same transaction
            // causes a System.CalloutException (Uncommitted work pending).
            // This wrapper is for cached JS clients.
            saveSignature(recordId, signatureBody);
            return 'Signature saved. Please refresh the page to enable full PDF generation capability (browser cache detected).';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public String isPreview { get; set; }
    public String recordId { get; set; }
    public String senderId { get; set; }
    public String sendDate { get; set; }

    public ProjectImprovementProgramPhotoCtrl() {
        isPreview = ApexPages.currentPage().getParameters().get('isPreview');
        recordId = ApexPages.currentPage().getParameters().get('Id');
        if (recordId == null) {
            recordId = ApexPages.currentPage().getParameters().get('recordId');
        }
        senderId = ApexPages.currentPage().getParameters().get('senderId');
        sendDate = ApexPages.currentPage().getParameters().get('sendDate');
    }

    // Properties for VF Page used for PDF
    public List<String> attestationList { get; set; }
    public String vfRecordId { get; set; }
    public String vfSenderId { get; set; }
    public String vfSendDate { get; set; }
    public String vfImgUrl { get; set; }
    public String vfSignerName { get; set; }
    public String vfCoSignerImgUrl { get; set; }
    public String vfCoSignerName { get; set; }
    public String vfCustomerName { get; set; }
    public String vfProjectAddress { get; set; }
    public String vfOrgName { get; set; }
    public SenderInfo senderDetails { get; set; }
    public String logoUrl { get; set; }
    public String currentRecordDate {get;set;}

    public void initPdf() {
        vfRecordId = ApexPages.currentPage().getParameters().get('recordId');
        vfSenderId = ApexPages.currentPage().getParameters().get('senderId');
        vfSendDate = ApexPages.currentPage().getParameters().get('sendDate');
        vfImgUrl = ApexPages.currentPage().getParameters().get('imgUrl');
        vfSignerName = ApexPages.currentPage().getParameters().get('signerName');
        vfCoSignerImgUrl = ApexPages.currentPage().getParameters().get('coSignerImgUrl');
        vfCoSignerName = ApexPages.currentPage().getParameters().get('coSignerName');
        
        attestationList = getAttestationItems();
        
        if (vfSenderId != null) {
            senderDetails = getSenderInfo(vfSenderId);
        }
        if (vfRecordId != null) {
            loadProjectDetails(vfRecordId);
        }
        try {
            vfOrgName = [SELECT Name FROM Organization LIMIT 1].Name;
        } catch (Exception e) {
            vfOrgName = '';
        }
        logoUrl = getLogoUrl();
        currentRecordDate = System.now().format('MM-dd-yyyy');
    }

    private static void cleanupSignatureFile(String signatureId) {
        if (String.isBlank(signatureId)) {
            return;
        }

        List<ContentVersion> cvs = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :signatureId LIMIT 1];
        if (!cvs.isEmpty()) {
            Database.delete(cvs[0].ContentDocumentId, false);
        }
    }

    private void loadProjectDetails(String projectId) {
        try {
            buildertek__Project__c projectRecord = [
                SELECT buildertek__Address__c,
                       buildertek__City_Text__c,
                       buildertek__State__c,
                       buildertek__Zip__c,
                       buildertek__Country__c,
                       buildertek__Customer__r.Name
                FROM buildertek__Project__c
                WHERE Id = :projectId
                LIMIT 1
            ];

            vfCustomerName = projectRecord.buildertek__Customer__r != null ? projectRecord.buildertek__Customer__r.Name : '';
            vfProjectAddress =
                String.valueOf(projectRecord.buildertek__Address__c == null ? '' : projectRecord.buildertek__Address__c) + ', ' +
                String.valueOf(projectRecord.buildertek__City_Text__c == null ? '' : projectRecord.buildertek__City_Text__c) + ' ' +
                String.valueOf(projectRecord.buildertek__State__c == null ? '' : projectRecord.buildertek__State__c) + ' -  ' +
                String.valueOf(projectRecord.buildertek__Zip__c == null ? '' : projectRecord.buildertek__Zip__c) + ', ' +
                String.valueOf(projectRecord.buildertek__Country__c == null ? '' : projectRecord.buildertek__Country__c);
        } catch (Exception e) {
            vfCustomerName = '';
            vfProjectAddress = '';
        }
    }
}
