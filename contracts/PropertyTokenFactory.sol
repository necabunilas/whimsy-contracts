// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPropertyToken.sol";
import "./PropertyToken.sol";

error NotOperator();
error Unauthorized();

contract PropertyTokenFactory is Ownable {
    struct Property {
        address token;
        address seller;
    }

    mapping(uint256 => Property) public properties;
    uint256 public propertyCount;
    address public immutable whimsy;

    event NewProperty(uint256 indexed propertyId, address tokenAddress);
    event SaleParametersSet(
        uint256 indexed propertyId,
        uint256 tokensForSale,
        uint256 price,
        uint256 sellerOwnership
    );
    event TokensPurchased(
        uint256 indexed propertyId,
        address buyer,
        uint256 amount
    );
    event SellerUpdated(uint256 indexed propertyId, address newSeller);
    event SupplyIncreased(uint256 indexed propertyId, uint256 newAmount);
    event Withdrawn(uint256 indexed propertyId, uint256 amount, address to);
    event ProposalCreated(
        uint256 indexed propertyId,
        uint256 proposalId,
        string description
    );
    event Voted(
        uint256 indexed propertyId,
        uint256 proposalId,
        address voter,
        bool support,
        uint256 weight
    );
    event ProposalFinalized(
        uint256 indexed propertyId,
        uint256 proposalId,
        bool passed
    );

    constructor(address whimsyAddress) Ownable(msg.sender) {
        whimsy = whimsyAddress;
    }

    // ========= Token Creation ==========

    // Add this event declaration along with your other events.
    event Clawback(
        uint256 indexed propertyId,
        address indexed tokenOwner,
        uint256 amount
    );

    // ...

    function createIPropertyToken(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address seller
    ) external onlyOwner returns (address token) {
        PropertyToken newToken = new PropertyToken(
            name,
            symbol,
            initialSupply,
            seller,
            whimsy
        );
        newToken.setOperator(address(this));

        propertyCount += 1;
        properties[propertyCount] = Property({
            token: address(newToken),
            seller: seller
        });

        emit NewProperty(propertyCount, address(newToken));
        return address(newToken);
    }

    // ========= Sale Management ==========

    function setSaleParameters(
        uint256 propertyId,
        uint256 tokensForSale,
        uint256 tokenPrice,
        uint256 sellerTargetOwnership
    ) external onlyOwner {
        Property memory p = properties[propertyId];
        IPropertyToken token = IPropertyToken(p.token);
        token.setSaleParameters(
            tokensForSale,
            tokenPrice,
            sellerTargetOwnership
        );
        emit SaleParametersSet(
            propertyId,
            tokensForSale,
            tokenPrice,
            sellerTargetOwnership
        );
    }

    function buyTokens(uint256 propertyId, uint256 amount) external payable {
        Property memory p = properties[propertyId];
        IPropertyToken token = IPropertyToken(p.token);
        token.buyTokens{value: msg.value}(amount);
        emit TokensPurchased(propertyId, msg.sender, amount);
    }

    function agreeDisclaimer(uint256 propertyId) external {
        Property memory p = properties[propertyId];
        IPropertyToken token = IPropertyToken(p.token);
        token.agreeDisclaimer();
    }

    function reserveTokens(
        uint256 propertyId,
        uint256 amount
    ) external payable {
        Property memory p = properties[propertyId];
        IPropertyToken token = IPropertyToken(p.token);
        token.reserveTokens{value: msg.value}(amount);
    }

    function refundUnagreedBuyer(
        uint256 propertyId,
        address buyer
    ) external onlyOwner {
        Property memory p = properties[propertyId];
        IPropertyToken token = IPropertyToken(p.token);
        token.refundUnagreedBuyer(buyer);
    }

    function increaseSupply(
        uint256 propertyId,
        uint256 amount
    ) external onlyOwner {
        Property memory p = properties[propertyId];
        IPropertyToken token = IPropertyToken(p.token);
        token.increaseSupply(amount);
        emit SupplyIncreased(propertyId, amount);
    }

    function updateSellerAddress(
        uint256 propertyId,
        address newSeller
    ) external {
        Property storage p = properties[propertyId];
        IPropertyToken token = IPropertyToken(p.token);
        if (msg.sender != p.seller) revert Unauthorized();

        p.seller = newSeller;
        token.updateSellerAddress(newSeller);
        emit SellerUpdated(propertyId, newSeller);
    }

    function clawback(
        uint256 propertyId,
        address tokenOwner
    ) external onlyOwner {
        Property memory p = properties[propertyId];
        require(p.token != address(0), "Invalid token address");

        IPropertyToken token = IPropertyToken(p.token);
        uint256 balance = token.balanceOf(tokenOwner);
        require(balance > 0, "No tokens to claw back");

        token.operatorTransfer(tokenOwner, owner(), balance);
        emit Clawback(propertyId, tokenOwner, balance);
    }

    // ========= Governance ==========

    function createProposal(
        uint256 propertyId,
        string memory description
    ) external onlyOwner {
        Property memory p = properties[propertyId];
        IPropertyToken token = IPropertyToken(p.token);
        uint256 proposalId = token.proposalsLength();
        token.createProposal(description);
        emit ProposalCreated(propertyId, proposalId, description);
    }

    function vote(
        uint256 propertyId,
        uint256 proposalId,
        bool support
    ) external {
        Property memory p = properties[propertyId];
        IPropertyToken token = IPropertyToken(p.token);
        token.vote(proposalId, support);
        uint256 weight = IPropertyToken(p.token).balanceOf(msg.sender);
        emit Voted(propertyId, proposalId, msg.sender, support, weight);
    }

    function finalizeProposal(
        uint256 propertyId,
        uint256 proposalId
    ) external onlyOwner {
        Property memory p = properties[propertyId];
        IPropertyToken token = IPropertyToken(p.token);
        token.finalizeProposal(proposalId);
        (, uint256 yesVotes, uint256 noVotes, bool finalized) = IPropertyToken(
            p.token
        ).getProposal(proposalId);
        emit ProposalFinalized(
            propertyId,
            proposalId,
            yesVotes > noVotes && finalized
        );
    }

    // ========= Getters ==========

    function getPostMoneyValuation(
        uint256 propertyId,
        uint256 preMoneyValuation
    ) external view returns (uint256) {
        Property memory p = properties[propertyId];
        IPropertyToken token = IPropertyToken(p.token);
        return token.getPostMoneyValuation(preMoneyValuation);
    }

    function getIPropertyToken(
        uint256 propertyId
    ) external view returns (address) {
        return properties[propertyId].token;
    }

    function getSeller(uint256 propertyId) external view returns (address) {
        return properties[propertyId].seller;
    }
}
