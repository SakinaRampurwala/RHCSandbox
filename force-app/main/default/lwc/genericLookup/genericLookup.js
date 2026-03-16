import { LightningElement, api, track } from 'lwc';
import retriveSearchDataApex from '@salesforce/apex/GenericLookupController.retriveSearchData';
import retrieveRecordsByIds from '@salesforce/apex/GenericLookupController.retrieveRecordsByIds';

export default class GenericLookup extends LightningElement {
    @api isMuiltiSelect;            // Deprecated api
    @api objectname = 'Contact';
    @api fieldNames = 'Id, Name';
    @api searchField = 'Name';
    @api searchCondition;
    @api label;
    @api iconName = 'standard:contact'
    @api placeholder = 'Search..';
    @api firstFieldToDisplay = 'Name';
    @api secondFieldToDisplay;

    @track searchRecords = [];
    @track selectedRecords = [];
    @track messageFlag = false;
    @track isSearchLoading = false;
    @track searchKey;
    @track dropdownOpen = false;

    delayTimeout;
    closeDropdownTimer;
    documentClickHandler;
    isMultiSelectValue = true;
    defaultSelectionRequestId = 0;

    @api
    get showLabel() {
        return this._showLabel;
    }
    set showLabel(value) {
        if (value === undefined || value === null) {
            this._showLabel = false;
            return;
        }
        this._showLabel = this.normalizeBoolean(value);
    }

    @api
    get defaultSelectedRecords() {
        return this._defaultSelectedRecords;
    }
    set defaultSelectedRecords(value) {
        this._defaultSelectedRecords = value;
        if (value) {
            this.defaultSelectionRequestId += 1;
            const requestId = this.defaultSelectionRequestId;
            this.primeDefaultSelection(value, requestId);
        }
    }

    @api
    get isMultiSelect() {
        return this.isMultiSelectValue;
    }
    set isMultiSelect(value) {
        const normalizedValue = this.normalizeBoolean(value);
        this.isMultiSelectValue = normalizedValue;
        this.enforceSelectionLimits();
    }

    get isMultiSelectMode() {
        return this.isMultiSelectValue;
    }

    get hasSelection() {
        return this.selectedRecords.length > 0;
    }

    get shouldShowInput() {
        return this.isMultiSelectValue || !this.hasSelection;
    }

    get singleSelectedRecord() {
        return this.hasSelection ? this.selectedRecords[0] : null;
    }

    get singleSelectedId() {
        return this.singleSelectedRecord ? this.singleSelectedRecord.Id : null;
    }

    get singleSelectedLabel() {
        const record = this.singleSelectedRecord;
        return record ? (record.displayLabel || record.Name || record.Id) : '';
    }

    get comboboxContainerClass() {
        return this.hasSelection ? 'slds-combobox_container slds-has-selection' : 'slds-combobox_container';
    }

    get isDropdownOpen() {
        return this.dropdownOpen;
    }

    get showDropdown() {
        return this.dropdownOpen && this.shouldShowInput;
    }

    get lookupInputClass() {
        const baseClass = 'lookupInputContainer slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click';
        return this.dropdownOpen ? `${baseClass} slds-is-open` : baseClass;
    }

    connectedCallback() {
        this.documentClickHandler = this.handleDocumentClick.bind(this);
        document.addEventListener('click', this.documentClickHandler);
    }

    disconnectedCallback() {
        if (this.documentClickHandler) {
            document.removeEventListener('click', this.documentClickHandler);
            this.documentClickHandler = null;
        }
        this.clearCloseDropdownTimer();
    }

    searchDataHelper() {
        var selectedRecordIds = [];

        this.selectedRecords.forEach(ele=>{
            selectedRecordIds.push(ele.Id);
        })

        retriveSearchDataApex({ 
            ObjectName: this.objectname, 
            fieldNames: this.fieldNames, 
            searchField: this.searchField, 
            searchValue: this.searchKey, 
            searchCondition: this.searchCondition, 
            selectedRecId: selectedRecordIds 
        })
        .then(result => {
            let searchRecords = [];
            result.forEach(element => {
                const formattedRecord = this.formatRecordForSelection(element);
                if (formattedRecord) {
                    searchRecords.push(formattedRecord);
                }
            });

            this.searchRecords = searchRecords;
            this.isSearchLoading = false;
            this.messageFlag = result.length === 0;
            this.updateDropdownVisibility();
        }).catch(error => {
            console.log('Error ==> ',error);
        });
    }

    // update searchKey property on input field change  
    handleKeyChange(event) {
        // Do not update the reactive property as long as this function is
        this.isSearchLoading = true;
        window.clearTimeout(this.delayTimeout);
        const searchKey = event.target.value;
        this.delayTimeout = setTimeout(() => {
            this.searchKey = searchKey;
            this.searchDataHelper();
        }, 300);
    }

    // method to toggle lookup result section on UI 
    handleSearchInputClick() {
        this.clearCloseDropdownTimer();
        this.searchDataHelper();
    }

    handleContainerMouseEnter() {
        this.clearCloseDropdownTimer();
    }

    handleContainerMouseLeave() {
        this.clearCloseDropdownTimer();
        this.closeDropdownTimer = window.setTimeout(() => {
            this.closeDropdown();
        }, 500);
    }

    setSelectedRecord(event) {
        const recId = event.currentTarget.dataset.id;
        if (!recId) {
            return;
        }

        const selectedRecord = this.searchRecords.find(data => data.Id === recId);
        if (!selectedRecord) {
            return;
        }

        const normalizedRecord = {
            ...selectedRecord,
            displayLabel: this.resolveDisplayLabel(selectedRecord)
        };

        const alreadySelected = this.selectedRecords.some(record => record.Id === recId);
        if (alreadySelected && this.isMultiSelectValue) {
            this.closeDropdown();
            this.clearSearchInput();
            return;
        }

        if (this.isMultiSelectValue) {
            this.selectedRecords = [...this.selectedRecords, normalizedRecord];
        } else {
            this.selectedRecords = [normalizedRecord];
        }

        this.closeDropdown();
        this.clearSearchInput();
        this.dispatchSelectedEvent();
    }

    removeRecord(event) {
        const recordId = event.detail?.name || event.currentTarget?.dataset?.id;
        this.removeSelectedRecordById(recordId);
    }

    handleSingleClear(event) {
        const recordId = event.currentTarget?.dataset?.id;
        this.removeSelectedRecordById(recordId);
    }

    dispatchSelectedEvent() {
        const normalizedRecords = this.selectedRecords.map(record => ({
            ...record,
            displayLabel: this.resolveDisplayLabel(record)
        }));

        this.selectedRecords = normalizedRecords;
        if (this.isMultiSelectValue) {
            const selectedEvent = new CustomEvent('selected', { detail: { selectedRecords: [...normalizedRecords] } });
            this.dispatchEvent(selectedEvent);
        } else {
            const selectedEvent = new CustomEvent('selected', { detail: { selectedRecord: normalizedRecords[0] } });
            this.dispatchEvent(selectedEvent);
        }
        
    }

    clearSearchInput() {
        this.searchKey = '';
        this.isSearchLoading = false;
        this.searchRecords = [];
        this.messageFlag = false;

        const searchInput = this.template.querySelector('lightning-input[data-id="userinput"]');
        if (searchInput) {
            searchInput.value = '';
        }
    }

    updateDropdownVisibility() {
        this.dropdownOpen = this.shouldShowInput && (this.searchRecords.length > 0 || this.messageFlag);
    }

    closeDropdown() {
        this.clearCloseDropdownTimer();
        this.dropdownOpen = false;
    }

    clearCloseDropdownTimer() {
        if (this.closeDropdownTimer) {
            window.clearTimeout(this.closeDropdownTimer);
            this.closeDropdownTimer = null;
        }
    }

    handleDocumentClick(event) {
        if (!this.dropdownOpen) {
            return;
        }

        const path = event.composedPath ? event.composedPath() : [];
        const clickedInside = path.includes(this.template.host) || this.template.contains(event.target);

        if (!clickedInside) {
            this.closeDropdown();
        }
    }

    normalizeBoolean(value) {
        if (value === undefined || value === null) {
            return true;
        }
        if (typeof value === 'string') {
            return value.toLowerCase() === 'true';
        }
        return Boolean(value);
    }

    enforceSelectionLimits() {
        if (this.isMultiSelectValue) {
            return;
        }

        if (this.selectedRecords.length > 1) {
            this.selectedRecords = [{ ...this.selectedRecords[0] }];
            this.dispatchSelectedEvent();
        }
    }

    removeSelectedRecordById(recordId) {
        if (!recordId) {
            return;
        }

        this.selectedRecords = this.selectedRecords.filter(record => record.Id !== recordId);
        this.dispatchSelectedEvent();

        if (!this.isMultiSelectValue) {
            // Give the DOM a chance to render the input before focusing it
            requestAnimationFrame(() => {
                const searchInput = this.template.querySelector('lightning-input[data-id="userinput"]');
                if (searchInput) {
                    searchInput.focus();
                }
            });
        }
    }

    resolveDisplayLabel(record) {
        if (!record) {
            return '';
        }

        const primaryFieldValue = this.firstFieldToDisplay ? record[this.firstFieldToDisplay] : null;
        return record.displayLabel || record.firstFieldValue || primaryFieldValue || record.Name || record.Id;
    }

    primeDefaultSelection(value, requestId) {
        const recordIds = this.normalizeDefaultRecordIds(value);

        if (!recordIds.length) {
            this.applyDefaultRecords([], requestId);
            return;
        }

        retrieveRecordsByIds({
            objectName: this.objectname,
            fieldNames: this.fieldNames,
            recordIds
        })
            .then(result => {
                this.applyDefaultRecords(result || [], requestId);
            })
            .catch(error => {
                console.error('Failed to seed default selections', error);
                this.applyDefaultRecords([], requestId);
            });
    }

    normalizeDefaultRecordIds(value) {
        if (value === undefined || value === null) {
            return [];
        }

        const items = Array.isArray(value) ? value : [value];
        const ids = [];

        items.forEach(item => {
            if (!item) {
                return;
            }

            if (typeof item === 'string' && item) {
                ids.push(item);
                return;
            }

            if (item.Id) {
                ids.push(item.Id);
            }
        });

        return ids;
    }

    applyDefaultRecords(records, requestId) {
        if (requestId !== this.defaultSelectionRequestId) {
            return;
        }

        const formattedRecords = (records || [])
            .map(record => this.formatRecordForSelection(record))
            .filter(Boolean);

        const normalizedRecords = this.isMultiSelectValue ? formattedRecords : formattedRecords.slice(0, 1);

        const incomingIds = normalizedRecords.map(record => record.Id);
        const existingIds = this.selectedRecords.map(record => record.Id);

        const sameLength = incomingIds.length === existingIds.length;
        const sameOrder = sameLength && incomingIds.every((id, index) => id === existingIds[index]);

        if (sameOrder) {
            return;
        }

        this.selectedRecords = normalizedRecords;
        this.dispatchSelectedEvent();
    }

    formatRecordForSelection(rawRecord) {
        if (!rawRecord) {
            return null;
        }

        const record = JSON.parse(JSON.stringify(rawRecord));
        record.firstFieldValue = record[this.firstFieldToDisplay];
        if (this.secondFieldToDisplay) {
            record.displaySecondField = true;
            record.secondFieldValue = record[this.secondFieldToDisplay];
        } else {
            record.displaySecondField = false;
            record.secondFieldValue = '';
        }
        record.displayLabel = this.resolveDisplayLabel(record);
        return record;
    }
}