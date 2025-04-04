// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPropertyToken {
    // --- Sale ---
    function withdraw() external;
    function setSaleParameters(
        uint256 tokensForSale,
        uint256 tokenPrice,
        uint256 targetSellerOwnership
    ) external;
    function buyTokens(uint256 amount) external payable;
    function operatorTransfer(address from, address to, uint256 amount) external;
    function increaseSupply(uint256 additionalTokens) external;
    function updateSellerAddress(address newSeller) external;
    function setOperator(address newOperator) external;
    function getPostMoneyValuation(uint256 preMoneyValuation) external view returns (uint256);

    // --- Disclaimer / Reservation ---
    function agreeDisclaimer() external;
    function reserveTokens(uint256 amount) external payable;
    function refundUnagreedBuyer(address buyer) external;

    // --- Governance ---
    function createProposal(string calldata description) external;
    function vote(uint256 proposalId, bool support) external;
    function finalizeProposal(uint256 proposalId) external;
    function getProposal(uint256 proposalId) external view returns (
        string memory description,
        uint256 yesVotes,
        uint256 noVotes,
        bool finalized
    );
    function proposalsLength() external view returns (uint256);

    // --- Voting Power ---
    function balanceOf(address account) external view returns (uint256);
}
