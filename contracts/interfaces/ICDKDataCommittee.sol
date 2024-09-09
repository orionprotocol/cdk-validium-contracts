// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

interface ICDKDataCommittee {
    function getAmountOfMembers() external view returns (uint256);
    function verifySignatures(bytes32 signedHash, bytes calldata signaturesAndAddrs) external view returns (address[] memory);
    function setupCommittee(uint256 _requiredAmountOfSignatures, string[] memory urls, bytes memory addrsBytes) external;
    function committeeHash() external view returns (bytes32);
    function requiredAmountOfSignatures() external view returns (uint256);
    function members(uint256 index) external view returns (string memory url, address addr);
}