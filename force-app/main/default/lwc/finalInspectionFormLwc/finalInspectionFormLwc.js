import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLogoUrl from '@salesforce/apex/FinalInspectionFormCtrl.getLogoUrl';
import getFinalInspectionData from '@salesforce/apex/FinalInspectionFormCtrl.getFinalInspectionData';
import saveSignature from '@salesforce/apex/FinalInspectionFormCtrl.saveSignature';
import savePdf from '@salesforce/apex/FinalInspectionFormCtrl.savePdf';

export default class FinalInspectionFormLwc extends LightningElement {
    @api isPreview;
    @api recordId;
    @api senderId;
    @api sendDate;

    @track isLoading = true;
    @track isSubmitted = false;
    @track isAlreadySubmitted = false;
    @track logoURL;
    @track inspectionData = {
        homeownerName: '',
        homeownerAddress: '',
        finalInspectionDate: ''
    };

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
        if (!this.recordId) {
            this.isLoading = false;
        }
    }

    get isReadOnly() {
        return this.isPreview === true || this.isPreview === 'true';
    }

    get signatureCanvasClass() {
        return `signature-pad${this.isReadOnly ? ' read-only' : ''}`;
    }

    get isSubmitDisabled() {
        return this.isReadOnly || !this.signatureState.homeowner || !this.signatureState.representative;
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
        this.signatureState[signatureId] = true;

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

    handleMouseUp() {
        this.isDrawing = false;
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
        this.signatureState[signatureId] = false;
    }

    handleSubmit() {
        this.isLoading = true;

        const homeownerCanvas = this.canvasMap.homeowner;
        const representativeCanvas = this.canvasMap.representative;
        if (!homeownerCanvas || !representativeCanvas) {
            this.isLoading = false;
            return;
        }

        const homeownerSignatureBody = homeownerCanvas
            .toDataURL('image/png')
            .replace(/^data:image\/(png|jpg);base64,/, '');
        const representativeSignatureBody = representativeCanvas
            .toDataURL('image/png')
            .replace(/^data:image\/(png|jpg);base64,/, '');

        Promise.all([
            saveSignature({
                recordId: this.recordId,
                signatureBody: homeownerSignatureBody,
                signatureLabel: 'Homeowner'
            }),
            saveSignature({
                recordId: this.recordId,
                signatureBody: representativeSignatureBody,
                signatureLabel: 'Program Representative'
            })
        ])
            .then(([homeownerResult, repResult]) => {
                return savePdf({
                    recordId: this.recordId,
                    senderId: this.senderId,
                    sendDate: this.sendDate,
                    homeownerImgUrl: homeownerResult?.imgUrl || '',
                    representativeImgUrl: repResult?.imgUrl || '',
                    homeownerSignatureId: homeownerResult?.cvId || '',
                    representativeSignatureId: repResult?.cvId || ''
                });
            })
            .then((result) => {
                if (result === 'Success') {
                    this.isSubmitted = true;
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: 'Final Inspection Form submitted successfully.',
                            variant: 'success'
                        })
                    );
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
