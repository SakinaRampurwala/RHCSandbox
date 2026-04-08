import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLogoUrl from '@salesforce/apex/FinalInspectionFormCtrl.getLogoUrl';
import getFinalInspectionData from '@salesforce/apex/FinalInspectionFormCtrl.getFinalInspectionData';
import saveSignature from '@salesforce/apex/FinalInspectionFormCtrl.saveSignature';
import savePdf from '@salesforce/apex/FinalInspectionFormCtrl.savePdf';
import sendCompanyContactEmail from '@salesforce/apex/FinalInspectionFormCtrl.sendCompanyContactEmail';

export default class FinalInspectionFormLwc extends LightningElement {
    @api isPreview;
    @api recordId;
    @api senderId;
    @api sendDate;

    @track isLoading = true;
    @track isSubmitted = false;
    @track isAlreadySubmitted = false;
    @track submitTitle = 'Thank You!';
    @track submitMessage = 'Final Inspection Form has been submitted successfully.';
    @track logoURL;
    @track homeownerSignatureUrl;
    @track representativeSignatureUrl;
    @track homeownerSigned = false;
    @track representativeSigned = false;
    @track inspectionData = {
        homeownerName: '',
        homeownerAddress: '',
        finalInspectionDate: ''
    };
    @track isVendor = false;
    @track isCompany = false;
    companyContactIds = [];
    companyEmails = [];
    fromAddressId;
    fileIds = [];

    canvasMap = {};
    ctxMap = {};
    isDrawing = false;
    activeSignatureId;
    signatureState = {
        homeowner: false,
        representative: false
    };

    currentDate = new Date().toLocaleDateString();

    @wire(getLogoUrl)
    wiredLogo({ error, data }) {
        if (data) {
            this.logoURL = data;
        } else if (error) {
            // no-op for non-critical UI element
        }
    }

    @wire(getFinalInspectionData, { recordId: '$recordId' })
    wiredInspection({ error, data }) {
        if (data) {
            const finalDate = data.finalInspectionDate || this.currentDate;
            const homeownerAddress = this.formatAddress({
                street: data.homeownerStreet,
                city: data.homeownerCity,
                state: data.homeownerState,
                postal: data.homeownerPostal,
                country: data.homeownerCountry
            });
            this.inspectionData = {
                homeownerName: data.homeownerName || '',
                homeownerAddress,
                finalInspectionDate: finalDate || ''
            };
            this.homeownerSignatureUrl = data.homeownerSignatureUrl || '';
            this.representativeSignatureUrl = data.representativeSignatureUrl || '';
            this.homeownerSigned = !!data.homeownerSigned;
            this.representativeSigned = !!data.representativeSigned;
            this.signatureState = {
                homeowner: this.homeownerSigned || !!this.homeownerSignatureUrl,
                representative: this.representativeSigned || !!this.representativeSignatureUrl
            };
            if (data.isFinalInspectionSubmitted) {
                this.isSubmitted = true;
                this.isAlreadySubmitted = true;
            }
        } else if (error) {
            this.inspectionData = {
                homeownerName: '',
                homeownerAddress: '',
                finalInspectionDate: ''
            };
        }
        this.isLoading = false;
    }

    connectedCallback() {
        const params = new URLSearchParams(window.location.search);
        this.isVendor = params.get('isVendor') === 'true';
        this.isCompany = params.get('isCompany') === 'true';
        const companyIdsParam = params.get('companyContactIds');
        if (companyIdsParam) {
            this.companyContactIds = companyIdsParam
                .split(',')
                .map(item => decodeURIComponent(item).trim())
                .filter(item => item);
        }
        const companyEmailsParam = params.get('companyEmails');
        if (companyEmailsParam) {
            this.companyEmails = companyEmailsParam
                .split(',')
                .map(item => decodeURIComponent(item).trim())
                .filter(item => item);
        }
        const fromAddressIdParam = params.get('fromAddressId');
        if (fromAddressIdParam) {
            this.fromAddressId = decodeURIComponent(fromAddressIdParam).trim();
        }
        const fileIdsParam = params.get('fileIds');
        if (fileIdsParam) {
            this.fileIds = fileIdsParam
                .split(',')
                .map(item => decodeURIComponent(item).trim())
                .filter(item => item);
        }
        if (!this.recordId) {
            this.isLoading = false;
        }
    }

    get showThankYouPage() {
        const previewFlag = this.isPreview === true || this.isPreview === 'true';
        if (previewFlag) {
            return false;
        }
        return this.isSubmitted;
    }

    get isReadOnly() {
        const previewFlag = this.isPreview === true || this.isPreview === 'true';
        if (this.isVendor || this.isCompany || this.isRepresentativeStage) {
            return false;
        }
        return previewFlag;
    }

    get isRepresentativeStage() {
        return this.hasHomeownerSignature && !this.hasRepresentativeSignature;
    }

    get showHomeownerSection() {
        if (this.isReadOnly) {
            return true;
        }
        if (this.isVendor || this.isCompany) {
            if (this.isVendor) {
                return true;
            }
            if (this.isCompany) {
                return this.hasHomeownerSignature;
            }
        }
        if (this.isRepresentativeStage) {
            return true;
        }
        return true;
    }

    get showRepresentativeSection() {
        if (this.isReadOnly) {
            return true;
        }
        if (this.isRepresentativeStage) {
            return true;
        }
        if (this.isVendor || this.isCompany) {
            return this.isCompany;
        }
        return true;
    }

    get signatureCanvasClass() {
        return `signature-pad${this.isReadOnly ? ' read-only' : ''}`;
    }

    get isSubmitDisabled() {
        if (this.isReadOnly) {
            return true;
        }
        if (this.isVendor || this.isCompany) {
            if (this.isVendor) {
                if (this.hasHomeownerSignature) {
                    return true;
                }
                return !this.signatureState.homeowner;
            }
            if (this.isCompany) {
                if (this.hasRepresentativeSignature) {
                    return true;
                }
                return !this.signatureState.representative;
            }
        }
        if (this.isRepresentativeStage) {
            return !this.signatureState.representative;
        }
        return !this.signatureState.homeowner || !this.signatureState.representative;
    }

    get hasHomeownerSignature() {
        return this.homeownerSigned || !!this.homeownerSignatureUrl;
    }

    get hasRepresentativeSignature() {
        return this.representativeSigned || !!this.representativeSignatureUrl;
    }

    formatAddress({ street, city, state, postal, country }) {
        const safeStreet = street || '';
        const safeCity = city || '';
        const safeState = state || '';
        const safePostal = postal || '';
        const safeCountry = country || '';

        const cityState = [safeCity, safeState].filter(Boolean).join(' ');
        const firstPart = [safeStreet, cityState].filter(Boolean).join(', ');
        const zipPart = safePostal ? ` - ${safePostal}` : '';
        const countryPart = safeCountry ? `, ${safeCountry}` : '';
        return `${firstPart}${zipPart}${countryPart}`.trim();
    }

    renderedCallback() {
        const canvases = this.template.querySelectorAll('canvas');
        if (!canvases || canvases.length === 0) {
            return;
        }

        canvases.forEach((canvas) => {
            const signatureId = canvas.dataset.signatureId;
            if (!signatureId || this.canvasMap[signatureId]) {
                return;
            }
            this.canvasMap[signatureId] = canvas;
            const ctx = canvas.getContext('2d');
            this.ctxMap[signatureId] = ctx;
            this.setCanvasSize(canvas, ctx);
        });
    }

    setCanvasSize(canvas, ctx) {
        canvas.width = canvas.offsetWidth;
        canvas.height = canvas.offsetHeight;
        ctx.lineWidth = 2;
        ctx.lineCap = 'round';
        ctx.strokeStyle = '#000';
    }

    handleMouseDown(event) {
        if (this.isReadOnly) return;
        const signatureId = event.target?.dataset?.signatureId;
        if (!signatureId || !this.ctxMap[signatureId]) return;

        this.isDrawing = true;
        this.activeSignatureId = signatureId;
        this.signatureState = { ...this.signatureState, [signatureId]: true };

        const canvas = this.canvasMap[signatureId];
        const ctx = this.ctxMap[signatureId];
        const { offsetX, offsetY } = this.getCoordinates(event, canvas);
        ctx.beginPath();
        ctx.moveTo(offsetX, offsetY);
    }

    handleMouseMove(event) {
        if (!this.isDrawing || this.isReadOnly) return;
        const signatureId = this.activeSignatureId;
        if (!signatureId || !this.ctxMap[signatureId]) return;
        const canvas = this.canvasMap[signatureId];
        const ctx = this.ctxMap[signatureId];
        const { offsetX, offsetY } = this.getCoordinates(event, canvas);
        ctx.lineTo(offsetX, offsetY);
        ctx.stroke();
    }

    handleMouseUp(event) {
        this.isDrawing = false;
        const signatureId = event?.target?.dataset?.signatureId || this.activeSignatureId;
        if (signatureId && this.canvasMap[signatureId]) {
            const hasSignature = this.hasSignatureOnCanvas(this.canvasMap[signatureId]);
            this.signatureState = { ...this.signatureState, [signatureId]: hasSignature };
        }
        this.activeSignatureId = null;
    }

    handleTouchStart(event) {
        if (this.isReadOnly) return;
        event.preventDefault();
        const touch = event.touches[0];
        const mouseEvent = new MouseEvent('mousedown', {
            clientX: touch.clientX,
            clientY: touch.clientY
        });
        event.target.dispatchEvent(mouseEvent);
    }

    handleTouchMove(event) {
        event.preventDefault();
        const touch = event.touches[0];
        const mouseEvent = new MouseEvent('mousemove', {
            clientX: touch.clientX,
            clientY: touch.clientY
        });
        event.target.dispatchEvent(mouseEvent);
    }

    handleTouchEnd(event) {
        event.preventDefault();
        const mouseEvent = new MouseEvent('mouseup', {});
        event.target.dispatchEvent(mouseEvent);
    }

    getCoordinates(event, canvas) {
        const rect = canvas.getBoundingClientRect();
        const clientX = event.clientX || event.touches?.[0].clientX;
        const clientY = event.clientY || event.touches?.[0].clientY;
        return {
            offsetX: clientX - rect.left,
            offsetY: clientY - rect.top
        };
    }

    clearSignature(event) {
        if (this.isReadOnly) return;
        const signatureId = event.target?.dataset?.signatureId;
        if (!signatureId || !this.canvasMap[signatureId] || !this.ctxMap[signatureId]) return;
        const canvas = this.canvasMap[signatureId];
        const ctx = this.ctxMap[signatureId];
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        this.signatureState = { ...this.signatureState, [signatureId]: false };
    }

    hasSignatureOnCanvas(canvas) {
        if (!canvas) {
            return false;
        }
        const ctx = canvas.getContext('2d');
        if (!ctx) {
            return false;
        }
        const pixelData = ctx.getImageData(0, 0, canvas.width, canvas.height);
        for (let i = 3; i < pixelData.data.length; i += 4) {
            if (pixelData.data[i] !== 0) {
                return true;
            }
        }
        return false;
    }

    handleSubmit() {
        if (this.isReadOnly) {
            return;
        }

        const signaturePromises = [];
        const signatureResults = {};

        const collectSignature = (signatureId, label, existingUrl, warningMessage) => {
            const canvas = this.canvasMap[signatureId];
            if (canvas && this.hasSignatureOnCanvas(canvas)) {
                const signatureBody = canvas.toDataURL('image/png').replace(/^data:image\/(png|jpg);base64,/, '');
                signaturePromises.push(
                    saveSignature({
                        recordId: this.recordId,
                        signatureBody,
                        signatureLabel: label
                    }).then((result) => {
                        signatureResults[signatureId] = result;
                    })
                );
                return true;
            }

            if (existingUrl) {
                signatureResults[signatureId] = { imgUrl: existingUrl, cvId: '' };
                return true;
            }

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Warning',
                    message: warningMessage,
                    variant: 'warning'
                })
            );
            return false;
        };

        if (this.showHomeownerSection) {
            const ok = collectSignature(
                'homeowner',
                'Homeowner',
                this.homeownerSignatureUrl,
                'Please provide the homeowner signature before submitting.'
            );
            if (!ok) {
                return;
            }
        }

        if (this.showRepresentativeSection) {
            const ok = collectSignature(
                'representative',
                'Program Representative',
                this.representativeSignatureUrl,
                'Please provide the program representative signature before submitting.'
            );
            if (!ok) {
                return;
            }
        }

        const hasAnySignature = signaturePromises.length > 0
            || signatureResults.homeowner
            || signatureResults.representative;
        if (!hasAnySignature) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Warning',
                    message: 'No signature found to save.',
                    variant: 'warning'
                })
            );
            return;
        }

        this.isLoading = true;

        Promise.all(signaturePromises)
            .then(() => {
                return savePdf({
                    recordId: this.recordId,
                    senderId: this.senderId,
                    sendDate: this.sendDate,
                    homeownerImgUrl: signatureResults.homeowner?.imgUrl || this.homeownerSignatureUrl || '',
                    representativeImgUrl: signatureResults.representative?.imgUrl || this.representativeSignatureUrl || '',
                    homeownerSignatureId: signatureResults.homeowner?.cvId || '',
                    representativeSignatureId: signatureResults.representative?.cvId || ''
                });
            })
            .then((result) => {
                if (result === 'Success') {
                    this.isSubmitted = true;
                    this.submitTitle = 'Thank You!';
                    this.submitMessage = 'Final Inspection Form has been submitted successfully.';
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: 'Final Inspection Form submitted successfully.',
                            variant: 'success'
                        })
                    );
                    return;
                }

                if (result === 'Already Submitted') {
                    this.isSubmitted = true;
                    this.isAlreadySubmitted = true;
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Already Submitted',
                            message: 'Final Inspection Form has already been submitted for this record.',
                            variant: 'info'
                        })
                    );
                    return;
                }

                if (result === 'Missing Signatures') {
                    if (this.isVendor) {
                        return sendCompanyContactEmail({
                            recordId: this.recordId,
                            companyContactIds: this.companyContactIds,
                            companyEmails: this.companyEmails,
                            senderId: this.senderId,
                            sendDate: this.sendDate,
                            fromAddressId: this.fromAddressId,
                            fileIds: this.fileIds
                        }).then((sendResult) => {
                            if (sendResult && sendResult !== 'Success') {
                                throw new Error(sendResult);
                            }
                            this.isSubmitted = true;
                            this.submitTitle = 'Thank You!';
                            this.submitMessage = 'Your signature has been saved. We will notify the program representative.';
                            this.dispatchEvent(
                                new ShowToastEvent({
                                    title: 'Success',
                                    message: 'Signature saved. The request has been sent to the program representative.',
                                    variant: 'success'
                                })
                            );
                        });
                    }

                    this.isSubmitted = true;
                    this.submitTitle = 'Thank You!';
                    this.submitMessage = 'Your signature has been saved. PDF will be generated once all signatures are collected.';
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Signature Saved',
                            message: 'Signature saved. PDF will be generated once all signatures are collected.',
                            variant: 'success'
                        })
                    );
                    return;
                }
            })
            .catch((error) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error?.body?.message || error?.message || 'An unknown error occurred',
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
}