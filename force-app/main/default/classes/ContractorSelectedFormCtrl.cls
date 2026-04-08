public class ContractorSelectedFormCtrl {
    public String isPreview { get; set; }
    public String recordId { get; set; }
    public String senderId { get; set; }
    public String sendDate { get; set; }

    public ContractorSelectedFormCtrl() {
        isPreview = ApexPages.currentPage().getParameters().get('isPreview');
        recordId = ApexPages.currentPage().getParameters().get('recordId');

        if (String.isBlank(recordId)) {
            recordId = ApexPages.currentPage().getParameters().get('id');
        }

        if (String.isBlank(recordId)) {
            recordId = ApexPages.currentPage().getParameters().get('Id');
        }

        senderId = ApexPages.currentPage().getParameters().get('senderId');
        sendDate = ApexPages.currentPage().getParameters().get('sendDate');
    }
}