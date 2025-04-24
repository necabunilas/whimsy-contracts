// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPropertyToken {
    // --- Sale ---
    function setSaleParameters(
        uint256 tokensForSale,
        uint256 tokenPrice,
        uint256 targetSellerOwnership
    ) external;
    function setSigner(address assignedSigner) external; 
    function buyTokensFor(address buyer, uint256 amount) external payable;
    function operatorTransfer(address from, address to, uint256 amount) external;
    function increaseSupply(uint256 additionalTokens) external;
    function updateSellerAddress(address newSeller) external;
    function getPostMoneyValuation(uint256 preMoneyValuation) external view returns (uint256);
    function pause() external;
    function unpause() external;
    function toggleTransfers(bool enabled) external;
    function setOperator(address newOperator) external;
    function withdrawPayment() external;
    function setWhimsy(address newWhimsy) external;
    function endSaleEarly() external;

    // --- Disclaimer / Reservation ---
    function agreeDisclaimer() external;
    function agreeDisclaimerFor(address buyer) external;
    function reserveTokensFor(address buyer, uint256 amount) external payable;
    function refundUnagreedBuyer(address buyer) external;

    // --- Governance ---
    function createProposal(string calldata description) external;
    function voteFor(address voter, uint256 proposalId, bool support) external;
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

    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;

    function tokenPrice() external view returns (uint256);
    function tokensForSale() external view returns (uint256);
    function targetSellerOwnership() external view returns (uint256);
    function totalRaised() external view returns (uint256);
    function totalReserved() external view returns (uint256);
    function saleSupplySnapshot() external view returns (uint256);
}
