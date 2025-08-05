// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title InheritanceOracle
 * @notice Oracle contract for verifying inheritance conditions
 * @dev Provides verification services for death certificates, legal documents, and other conditions
 */
contract InheritanceOracle is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;

    // Verification types
    enum VerificationType {
        DEATH_CERTIFICATE,
        LEGAL_DOCUMENT,
        MEDICAL_CERTIFICATE,
        COURT_ORDER,
        CUSTOM_CONDITION
    }

    // Verification status
    enum VerificationStatus {
        PENDING,
        VERIFIED,
        REJECTED,
        EXPIRED
    }

    // Verification request structure
    struct VerificationRequest {
        address requester;
        address safe;
        address beneficiary;
        VerificationType verificationType;
        string documentHash; // IPFS hash or other document identifier
        uint256 requestTime;
        uint256 expiryTime;
        VerificationStatus status;
        string rejectionReason;
        address verifier;
    }

    // Authorized verifiers for different types
    mapping(VerificationType => mapping(address => bool)) public authorizedVerifiers;
    mapping(bytes32 => VerificationRequest) public verificationRequests;
    mapping(address => bytes32[]) public safeVerifications;
    
    // Settings
    uint256 public defaultExpiryPeriod = 365 days;
    uint256 public verificationFee = 0.01 ether;
    
    // Events
    event VerificationRequested(
        bytes32 indexed requestId,
        address indexed safe,
        address indexed beneficiary,
        VerificationType verificationType
    );
    
    event VerificationCompleted(
        bytes32 indexed requestId,
        VerificationStatus status,
        address verifier
    );
    
    event VerifierAuthorized(
        VerificationType verificationType,
        address verifier,
        bool authorized
    );

    // Errors
    error UnauthorizedVerifier();
    error InvalidRequest();
    error RequestExpired();
    error InsufficientFee();
    error RequestNotFound();
    error AlreadyProcessed();

    /**
     * @notice Request verification for inheritance conditions
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary
     * @param verificationType Type of verification required
     * @param documentHash Hash of the supporting document
     * @param customExpiryTime Custom expiry time (0 for default)
     */
    function requestVerification(
        address safe,
        address beneficiary,
        VerificationType verificationType,
        string calldata documentHash,
        uint256 customExpiryTime
    ) external payable nonReentrant returns (bytes32 requestId) {
        if (msg.value < verificationFee) revert InsufficientFee();
        
        uint256 expiryTime = customExpiryTime > 0 
            ? customExpiryTime 
            : block.timestamp + defaultExpiryPeriod;
            
        requestId = keccak256(abi.encodePacked(
            msg.sender,
            safe,
            beneficiary,
            verificationType,
            documentHash,
            block.timestamp
        ));
        
        verificationRequests[requestId] = VerificationRequest({
            requester: msg.sender,
            safe: safe,
            beneficiary: beneficiary,
            verificationType: verificationType,
            documentHash: documentHash,
            requestTime: block.timestamp,
            expiryTime: expiryTime,
            status: VerificationStatus.PENDING,
            rejectionReason: "",
            verifier: address(0)
        });
        
        safeVerifications[safe].push(requestId);
        
        emit VerificationRequested(requestId, safe, beneficiary, verificationType);
        return requestId;
    }

    /**
     * @notice Complete verification (approve or reject)
     * @param requestId ID of the verification request
     * @param approved Whether the verification is approved
     * @param rejectionReason Reason for rejection (if applicable)
     */
    function completeVerification(
        bytes32 requestId,
        bool approved,
        string calldata rejectionReason
    ) external nonReentrant {
        VerificationRequest storage request = verificationRequests[requestId];
        
        if (request.requester == address(0)) revert RequestNotFound();
        if (request.status != VerificationStatus.PENDING) revert AlreadyProcessed();
        if (block.timestamp > request.expiryTime) revert RequestExpired();
        if (!authorizedVerifiers[request.verificationType][msg.sender]) {
            revert UnauthorizedVerifier();
        }
        
        request.status = approved ? VerificationStatus.VERIFIED : VerificationStatus.REJECTED;
        request.rejectionReason = rejectionReason;
        request.verifier = msg.sender;
        
        emit VerificationCompleted(requestId, request.status, msg.sender);
    }

    /**
     * @notice Generate verification proof for inheritance execution
     * @param requestId ID of the verified request
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary
     * @return proof Cryptographic proof for inheritance execution
     */
    function generateVerificationProof(
        bytes32 requestId,
        address safe,
        address beneficiary
    ) external view returns (bytes memory proof) {
        VerificationRequest memory request = verificationRequests[requestId];
        
        if (request.status != VerificationStatus.VERIFIED) revert InvalidRequest();
        if (request.safe != safe || request.beneficiary != beneficiary) revert InvalidRequest();
        if (block.timestamp > request.expiryTime) revert RequestExpired();
        
        // Create a message hash that includes the verification details
        bytes32 message = keccak256(abi.encodePacked(
            requestId,
            safe,
            beneficiary,
            request.verificationType,
            request.verifier,
            block.timestamp / 1 days // Valid for the current day
        ));
        
        // In a real implementation, this would be signed by the oracle's private key
        // For this example, we return the message hash as proof
        return abi.encodePacked(message);
    }

    /**
     * @notice Verify a proof generated by this oracle
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary
     * @param proof Proof to verify
     * @return isValid Whether the proof is valid
     */
    function verifyProof(
        address safe,
        address beneficiary,
        bytes calldata proof
    ) external view returns (bool isValid) {
        if (proof.length != 32) return false;
        
        bytes32 providedHash = abi.decode(proof, (bytes32));
        
        // Check if this hash corresponds to a valid verification
        bytes32[] memory safeRequests = safeVerifications[safe];
        for (uint256 i = 0; i < safeRequests.length; i++) {
            VerificationRequest memory request = verificationRequests[safeRequests[i]];
            
            if (request.status == VerificationStatus.VERIFIED &&
                request.beneficiary == beneficiary &&
                block.timestamp <= request.expiryTime) {
                
                bytes32 expectedHash = keccak256(abi.encodePacked(
                    safeRequests[i],
                    safe,
                    beneficiary,
                    request.verificationType,
                    request.verifier,
                    block.timestamp / 1 days
                ));
                
                if (providedHash == expectedHash) {
                    return true;
                }
            }
        }
        
        return false;
    }

    /**
     * @notice Authorize or deauthorize a verifier for a specific verification type
     * @param verificationType Type of verification
     * @param verifier Address of the verifier
     * @param authorized Whether the verifier is authorized
     */
    function setVerifierAuthorization(
        VerificationType verificationType,
        address verifier,
        bool authorized
    ) external onlyOwner {
        authorizedVerifiers[verificationType][verifier] = authorized;
        emit VerifierAuthorized(verificationType, verifier, authorized);
    }

    /**
     * @notice Update oracle settings
     * @param _defaultExpiryPeriod Default expiry period for verifications
     * @param _verificationFee Fee for requesting verification
     */
    function updateSettings(
        uint256 _defaultExpiryPeriod,
        uint256 _verificationFee
    ) external onlyOwner {
        defaultExpiryPeriod = _defaultExpiryPeriod;
        verificationFee = _verificationFee;
    }

    /**
     * @notice Withdraw accumulated fees
     * @param to Address to send fees to
     */
    function withdrawFees(address payable to) external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        to.transfer(balance);
    }

    /**
     * @notice Get verification request details
     * @param requestId ID of the verification request
     * @return request Verification request details
     */
    function getVerificationRequest(bytes32 requestId) 
        external 
        view 
        returns (VerificationRequest memory request) 
    {
        return verificationRequests[requestId];
    }

    /**
     * @notice Get all verification requests for a Safe
     * @param safe Address of the Safe wallet
     * @return requestIds Array of request IDs
     */
    function getSafeVerifications(address safe) 
        external 
        view 
        returns (bytes32[] memory requestIds) 
    {
        return safeVerifications[safe];
    }

    /**
     * @notice Check if a verifier is authorized for a verification type
     * @param verificationType Type of verification
     * @param verifier Address of the verifier
     * @return authorized Whether the verifier is authorized
     */
    function isAuthorizedVerifier(
        VerificationType verificationType,
        address verifier
    ) external view returns (bool authorized) {
        return authorizedVerifiers[verificationType][verifier];
    }
}
