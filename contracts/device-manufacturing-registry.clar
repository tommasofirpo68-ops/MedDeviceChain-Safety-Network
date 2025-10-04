;; Device Manufacturing Registry Contract
;; Track medical device production batches, quality control tests, and FDA approval status

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-ALREADY-EXISTS (err u2))
(define-constant ERR-NOT-FOUND (err u3))
(define-constant ERR-INVALID-INPUT (err u4))
(define-constant ERR-INVALID-STATUS (err u5))
(define-constant ERR-BATCH-FINALIZED (err u6))

;; Contract deployer
(define-constant CONTRACT-OWNER tx-sender)

;; Device batch status constants
(define-constant STATUS-PENDING u1)
(define-constant STATUS-IN-PROGRESS u2)
(define-constant STATUS-QC-PASSED u3)
(define-constant STATUS-QC-FAILED u4)
(define-constant STATUS-FDA-APPROVED u5)
(define-constant STATUS-FDA-REJECTED u6)
(define-constant STATUS-FINALIZED u7)
(define-constant STATUS-RECALLED u8)

;; Device batch structure
(define-map device-batches
    { batch-id: (string-ascii 64) }
    {
        manufacturer: principal,
        device-type: (string-ascii 128),
        batch-size: uint,
        production-date: uint,
        expiry-date: uint,
        manufacturing-facility: (string-ascii 256),
        batch-status: uint,
        qc-test-results: (string-ascii 512),
        fda-approval-number: (optional (string-ascii 128)),
        lot-number: (string-ascii 128),
        created-at: uint,
        updated-at: uint,
        serial-number-range-start: uint,
        serial-number-range-end: uint,
        components-list: (string-ascii 1024)
    }
)

;; Quality control test records
(define-map qc-test-records
    { batch-id: (string-ascii 64), test-id: (string-ascii 64) }
    {
        test-type: (string-ascii 128),
        test-date: uint,
        test-result: bool,
        test-score: uint,
        test-notes: (string-ascii 512),
        tested-by: principal,
        test-location: (string-ascii 256),
        test-parameters: (string-ascii 512)
    }
)

;; Manufacturer registry
(define-map manufacturer-registry
    { manufacturer: principal }
    {
        company-name: (string-ascii 256),
        license-number: (string-ascii 128),
        certification-status: bool,
        registration-date: uint,
        contact-info: (string-ascii 512),
        facility-count: uint,
        compliance-score: uint
    }
)

;; FDA approval tracking
(define-map fda-approvals
    { approval-number: (string-ascii 128) }
    {
        batch-id: (string-ascii 64),
        approval-date: uint,
        approval-type: (string-ascii 64),
        regulatory-pathway: (string-ascii 128),
        conditions: (string-ascii 1024),
        expiry-date: uint,
        approved-by: (string-ascii 256)
    }
)

;; Batch counter for unique ID generation
(define-data-var batch-counter uint u0)

;; Authorized quality control testers
(define-map authorized-qc-testers
    { tester: principal }
    { authorized: bool, authorization-date: uint }
)

;; Authorized FDA representatives
(define-map authorized-fda-reps
    { representative: principal }
    { authorized: bool, authorization-date: uint }
)

;; Register a new manufacturer
(define-public (register-manufacturer
    (company-name (string-ascii 256))
    (license-number (string-ascii 128))
    (contact-info (string-ascii 512))
)
    (let
        (
            (manufacturer tx-sender)
        )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (> (len company-name) u0) ERR-INVALID-INPUT)
        (asserts! (> (len license-number) u0) ERR-INVALID-INPUT)
        
        (map-set manufacturer-registry
            { manufacturer: manufacturer }
            {
                company-name: company-name,
                license-number: license-number,
                certification-status: true,
                registration-date: stacks-block-height,
                contact-info: contact-info,
                facility-count: u1,
                compliance-score: u100
            }
        )
        (ok true)
    )
)

;; Register a new device batch
(define-public (register-batch
    (batch-id (string-ascii 64))
    (device-type (string-ascii 128))
    (batch-size uint)
    (production-date uint)
    (expiry-date uint)
    (manufacturing-facility (string-ascii 256))
    (lot-number (string-ascii 128))
    (serial-start uint)
    (serial-end uint)
    (components (string-ascii 1024))
)
    (let
        (
            (manufacturer tx-sender)
        )
        (asserts! (is-some (map-get? manufacturer-registry { manufacturer: manufacturer })) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (map-get? device-batches { batch-id: batch-id })) ERR-ALREADY-EXISTS)
        (asserts! (> batch-size u0) ERR-INVALID-INPUT)
        (asserts! (> expiry-date production-date) ERR-INVALID-INPUT)
        (asserts! (>= serial-end serial-start) ERR-INVALID-INPUT)
        
        (map-set device-batches
            { batch-id: batch-id }
            {
                manufacturer: manufacturer,
                device-type: device-type,
                batch-size: batch-size,
                production-date: production-date,
                expiry-date: expiry-date,
                manufacturing-facility: manufacturing-facility,
                batch-status: STATUS-PENDING,
                qc-test-results: "",
                fda-approval-number: none,
                lot-number: lot-number,
                created-at: stacks-block-height,
                updated-at: stacks-block-height,
                serial-number-range-start: serial-start,
                serial-number-range-end: serial-end,
                components-list: components
            }
        )
        
        (var-set batch-counter (+ (var-get batch-counter) u1))
        (ok true)
    )
)

;; Update batch status
(define-public (update-batch-status
    (batch-id (string-ascii 64))
    (new-status uint)
)
    (let
        (
            (batch-data (unwrap! (map-get? device-batches { batch-id: batch-id }) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get manufacturer batch-data)) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-status STATUS-RECALLED) ERR-INVALID-STATUS)
        (asserts! (not (is-eq (get batch-status batch-data) STATUS-FINALIZED)) ERR-BATCH-FINALIZED)
        
        (map-set device-batches
            { batch-id: batch-id }
            (merge batch-data { batch-status: new-status, updated-at: stacks-block-height })
        )
        (ok true)
    )
)

;; Add QC test record
(define-public (add-qc-test
    (batch-id (string-ascii 64))
    (test-id (string-ascii 64))
    (test-type (string-ascii 128))
    (test-result bool)
    (test-score uint)
    (test-notes (string-ascii 512))
    (test-location (string-ascii 256))
    (test-parameters (string-ascii 512))
)
    (let
        (
            (batch-data (unwrap! (map-get? device-batches { batch-id: batch-id }) ERR-NOT-FOUND))
            (tester tx-sender)
        )
        (asserts! (default-to false (get authorized (map-get? authorized-qc-testers { tester: tester }))) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (map-get? qc-test-records { batch-id: batch-id, test-id: test-id })) ERR-ALREADY-EXISTS)
        (asserts! (<= test-score u100) ERR-INVALID-INPUT)
        
        (map-set qc-test-records
            { batch-id: batch-id, test-id: test-id }
            {
                test-type: test-type,
                test-date: stacks-block-height,
                test-result: test-result,
                test-score: test-score,
                test-notes: test-notes,
                tested-by: tester,
                test-location: test-location,
                test-parameters: test-parameters
            }
        )
        (ok true)
    )
)

;; Set FDA approval
(define-public (set-fda-approval
    (batch-id (string-ascii 64))
    (approval-number (string-ascii 128))
    (approval-type (string-ascii 64))
    (regulatory-pathway (string-ascii 128))
    (conditions (string-ascii 1024))
    (approval-expiry uint)
    (approved-by (string-ascii 256))
)
    (let
        (
            (batch-data (unwrap! (map-get? device-batches { batch-id: batch-id }) ERR-NOT-FOUND))
            (fda-rep tx-sender)
        )
        (asserts! (default-to false (get authorized (map-get? authorized-fda-reps { representative: fda-rep }))) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (map-get? fda-approvals { approval-number: approval-number })) ERR-ALREADY-EXISTS)
        (asserts! (> approval-expiry stacks-block-height) ERR-INVALID-INPUT)
        
        ;; Update batch with FDA approval
        (map-set device-batches
            { batch-id: batch-id }
            (merge batch-data 
                { 
                    fda-approval-number: (some approval-number),
                    batch-status: STATUS-FDA-APPROVED,
                    updated-at: stacks-block-height 
                }
            )
        )
        
        ;; Record FDA approval details
        (map-set fda-approvals
            { approval-number: approval-number }
            {
                batch-id: batch-id,
                approval-date: stacks-block-height,
                approval-type: approval-type,
                regulatory-pathway: regulatory-pathway,
                conditions: conditions,
                expiry-date: approval-expiry,
                approved-by: approved-by
            }
        )
        (ok true)
    )
)

;; Authorize QC tester
(define-public (authorize-qc-tester (tester principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (map-set authorized-qc-testers
            { tester: tester }
            { authorized: true, authorization-date: stacks-block-height }
        )
        (ok true)
    )
)

;; Authorize FDA representative
(define-public (authorize-fda-representative (representative principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (map-set authorized-fda-reps
            { representative: representative }
            { authorized: true, authorization-date: stacks-block-height }
        )
        (ok true)
    )
)

;; Get batch information
(define-read-only (get-batch-info (batch-id (string-ascii 64)))
    (map-get? device-batches { batch-id: batch-id })
)

;; Get QC test record
(define-read-only (get-qc-test (batch-id (string-ascii 64)) (test-id (string-ascii 64)))
    (map-get? qc-test-records { batch-id: batch-id, test-id: test-id })
)

;; Get manufacturer info
(define-read-only (get-manufacturer-info (manufacturer principal))
    (map-get? manufacturer-registry { manufacturer: manufacturer })
)

;; Get FDA approval info
(define-read-only (get-fda-approval (approval-number (string-ascii 128)))
    (map-get? fda-approvals { approval-number: approval-number })
)

;; Get batch counter
(define-read-only (get-batch-counter)
    (var-get batch-counter)
)

;; Check if QC tester is authorized
(define-read-only (is-authorized-qc-tester (tester principal))
    (default-to false (get authorized (map-get? authorized-qc-testers { tester: tester })))
)

;; Check if FDA representative is authorized
(define-read-only (is-authorized-fda-rep (representative principal))
    (default-to false (get authorized (map-get? authorized-fda-reps { representative: representative })))
)

;; title: device-manufacturing-registry
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

