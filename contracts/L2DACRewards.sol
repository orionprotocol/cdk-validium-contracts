// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@hyperlane-xyz/core/interfaces/IMailbox.sol";

contract L2DACRewards is Ownable, Pausable {
    IERC721 public licenseNFT;
    IERC20 public rewardsToken;
    IMailbox public mailbox;
    uint32 public originDomain;
    address public l1DACRewardsAddress;
    
    struct DelegatorRewards {
        uint256 accumulatedRewards;
        uint256 lastClaimTimestamp;
    }
    
    mapping(address => uint256) public delegatedLicenses;
    mapping(address => DelegatorRewards) public delegatorRewards;
    mapping(uint256 => address) public licenseDelegate;

    uint256 public constant CLAIM_PERIOD = 7 days;
    
    event LicenseDelegated(uint256 tokenId, address delegator, address daMember);
    event RewardsClaimed(address delegator, uint256 amount);
    event RewardsReceived(address daMember, uint256 amount);

    constructor(
        address _licenseNFT,
        address _rewardsToken,
        address _mailbox,
        uint32 _originDomain,
        address _l1DACRewardsAddress
    ) {
        licenseNFT = IERC721(_licenseNFT);
        rewardsToken = IERC20(_rewardsToken);
        mailbox = IMailbox(_mailbox);
        originDomain = _originDomain;
        l1DACRewardsAddress = _l1DACRewardsAddress;
    }

    function delegateLicense(uint256 tokenId, address daMember) external {
        require(licenseNFT.ownerOf(tokenId) == msg.sender, "Not the owner of the license");
        
        if (licenseDelegate[tokenId] != address(0)) {
            address previousDelegate = licenseDelegate[tokenId];
            delegatedLicenses[previousDelegate]--;
        }
        
        licenseDelegate[tokenId] = daMember;
        delegatedLicenses[daMember]++;
        
        emit LicenseDelegated(tokenId, msg.sender, daMember);
        
        // Send a message to L1 about the new delegation
        bytes memory message = abi.encode(daMember, delegatedLicenses[daMember]);
        mailbox.dispatch(originDomain, bytes32(uint256(uint160(l1DACRewardsAddress))), message);
    }
    
    function undelegateLicense(uint256 tokenId) external {
        require(licenseNFT.ownerOf(tokenId) == msg.sender, "Not the owner of the license");
        address delegate = licenseDelegate[tokenId];
        require(delegate != address(0), "License not delegated");
        
        delegatedLicenses[delegate]--;
        licenseDelegate[tokenId] = address(0);
        
        emit LicenseDelegated(tokenId, msg.sender, address(0));
        
        // Send a message to L1 about the undelegation
        bytes memory message = abi.encode(delegate, delegatedLicenses[delegate]);
        mailbox.dispatch(originDomain, bytes32(uint256(uint160(l1DACRewardsAddress))), message);
    }
    
    function claimRewards() external {
        DelegatorRewards storage rewards = delegatorRewards[msg.sender];
        require(block.timestamp >= rewards.lastClaimTimestamp + CLAIM_PERIOD, "Claim period not elapsed");
        
        uint256 rewardAmount = rewards.accumulatedRewards;
        rewards.accumulatedRewards = 0;
        rewards.lastClaimTimestamp = block.timestamp;
        
        require(rewardsToken.transfer(msg.sender, rewardAmount), "Reward transfer failed");
        
        emit RewardsClaimed(msg.sender, rewardAmount);
    }
    
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _message) external {
        require(msg.sender == address(mailbox), "Only mailbox can call handle");
        require(_origin == originDomain, "Invalid origin");
        require(_sender == bytes32(uint256(uint160(l1DACRewardsAddress))), "Invalid sender");
        
        (address daMember, uint256 rewardAmount) = abi.decode(_message, (address, uint256));
        
        uint256 totalDelegatedLicenses = delegatedLicenses[daMember];
        if (totalDelegatedLicenses > 0) {
            uint256 rewardPerLicense = rewardAmount / totalDelegatedLicenses;
            for (uint256 i = 0; i < licenseNFT.totalSupply(); i++) {
                if (licenseDelegate[i] == daMember) {
                    address delegator = licenseNFT.ownerOf(i);
                    delegatorRewards[delegator].accumulatedRewards += rewardPerLicense;
                }
            }
        }
        
        emit RewardsReceived(daMember, rewardAmount);
    }
}
