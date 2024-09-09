// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./ICDKDataCommittee.sol";
import "@hyperlane-xyz/core/interfaces/IMailbox.sol";
import "@hyperlane-xyz/core/interfaces/IInterchainGasPaymaster.sol";

contract L1DACRewards is Ownable, Pausable {
    IERC20 public rewardsToken;
    ICDKDataCommittee public dataCommittee;
    IMailbox public mailbox;
    IInterchainGasPaymaster public igp;
    uint32 public destinationDomain;
    
    struct DAMemberRewards {
        uint256 accumulatedRewards;
        uint256 lastClaimTimestamp;
        uint256 delegatedLicenses;
        uint256 rewardPerShare;
    }
    
    mapping(address => DAMemberRewards) public daMemberRewards;

    uint256 public constant CLAIM_PERIOD = 7 days;
    uint256 public constant MAX_FEE_PERCENTAGE = 30;
    uint256 public rewardPerSignature;
    
    event RewardsClaimed(address daMember, uint256 amount);
    event RewardsCompounded(address indexed daMember, uint256 amount);
    event ParticipationRecorded(address[] participants, uint256 signatureCount);
    event RewardPerSignatureUpdated(uint256 newRewardPerSignature);

    constructor(
        address _rewardsToken,
        address _dataCommittee,
        address _mailbox,
        address _igp,
        uint32 _destinationDomain
    ) {
        rewardsToken = IERC20(_rewardsToken);
        dataCommittee = ICDKDataCommittee(_dataCommittee);
        mailbox = IMailbox(_mailbox);
        igp = IInterchainGasPaymaster(_igp);
        destinationDomain = _destinationDomain;
    }

    function updateFeePercentage(uint256 _newFeePercentage) external {
        require(dataCommittee.isMember(msg.sender), "Not an active DA member");
        
        // Update the fee percentage
        dataCommittee.updateFeePercentage(msg.sender, _newFeePercentage);
    }   

    // function compoundRewards() external {
    //     require(dataCommittee.isMember(msg.sender), "Not an active DA member");
    //     DAMemberRewards storage rewards = daMemberRewards[msg.sender];
    //     require(block.timestamp >= rewards.lastClaimTimestamp + CLAIM_PERIOD, "Claim period not elapsed");
        
    //     uint256 rewardAmount = rewards.accumulatedRewards;
    //     uint256 fee = (rewardAmount * dataCommittee.getFeePercentage(msg.sender)) / 100;
    //     uint256 compoundAmount = rewardAmount - fee;
        
    //     rewards.accumulatedRewards = 0;
    //     rewards.lastClaimTimestamp = block.timestamp;
        
    //     require(rewardsToken.transfer(msg.sender, fee), "Fee transfer failed");
    //     // Compound the rewards by adding them to the accumulated rewards
    //     rewards.accumulatedRewards += compoundAmount;
        
    //     // Update the reward per share for delegators
    //     if (rewards.delegatedLicenses > 0) {
    //         rewards.rewardPerShare += compoundAmount / rewards.delegatedLicenses;
    //     }
    //     dataCommittee.updateStake(msg.sender, compoundAmount);
        
    //     emit RewardsCompounded(msg.sender, compoundAmount);
    // }
    
    function recordParticipation(address[] calldata participants, uint256 signatureCount) external onlyOwner {
        uint256 rewardAmount = rewardPerSignature * signatureCount;
        for (uint256 i = 0; i < participants.length; i++) {
            address member = participants[i];
            if (dataCommittee.isMember(member)) {
                DAMemberRewards storage rewards = daMemberRewards[member];
                rewards.accumulatedRewards += rewardAmount;
                if (rewards.delegatedLicenses > 0) {
                    rewards.rewardPerShare += rewardAmount / rewards.delegatedLicenses;
                }
            }
        }
        emit ParticipationRecorded(participants, signatureCount);
    }
    
    function claimRewards() external {
        require(dataCommittee.isMember(msg.sender), "Not an active DA member");
        DAMemberRewards storage rewards = daMemberRewards[msg.sender];
        require(block.timestamp >= rewards.lastClaimTimestamp + CLAIM_PERIOD, "Claim period not elapsed");
        
        uint256 rewardAmount = rewards.accumulatedRewards;
        uint256 fee = (rewardAmount * dataCommittee.getFeePercentage(msg.sender)) / 100;
        uint256 delegatorReward = rewardAmount - fee;
        
        rewards.accumulatedRewards = 0;
        rewards.lastClaimTimestamp = block.timestamp;
        
        require(rewardsToken.transfer(msg.sender, fee), "Reward transfer failed");
        
        // Send a message to L2 to update the rewards there
        bytes memory message = abi.encode(msg.sender, delegatorReward);
        uint256 messageFee = igp.quoteGasPayment(destinationDomain, 200000);
        mailbox.dispatch{value: messageFee}(
            destinationDomain,
            bytes32(uint256(uint160(address(this)))),
            message
        );
        
        emit RewardsClaimed(msg.sender, rewardAmount);
    }
    
    function setRewardPerSignature(uint256 _rewardPerSignature) external onlyOwner {
        rewardPerSignature = _rewardPerSignature;
        emit RewardPerSignatureUpdated(_rewardPerSignature);
    }

    // This function will be called by the Hyperlane relayer to update delegated licenses
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _message) external {
        require(msg.sender == address(mailbox), "Only mailbox can call handle");
        require(_origin == destinationDomain, "Invalid origin");
        
        (address daMember, uint256 licenseCount) = abi.decode(_message, (address, uint256));
        daMemberRewards[daMember].delegatedLicenses = licenseCount;
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
}
