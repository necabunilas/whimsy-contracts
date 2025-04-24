// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IPropertyToken.sol";
import "./PropertyToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error Unauthorized();

contract PropertyTokenFactory is Ownable, Pausable {
    IERC20 public immutable paymentToken;
    struct Property {
        address token;
        address seller;
    }
    mapping(uint256 => Property) public properties;
    uint256 public propertyCount;
    address public whimsy;
    uint8 private constant PCT_BASE = 100;
    uint8 private constant WHIMSY_PCT = 3;
    address private signer;

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
    event Clawback(
        uint256 indexed propertyId,
        address indexed tokenOwner,
        uint256 amount
    );
    event TokenOwnershipTransferred(
        uint256 indexed propertyId,
        address indexed previousOwner,
        address indexed newOwner
    );
    event WhimsyUpdated(address indexed oldWhimsy, address indexed newWhimsy);

    constructor(
        address whimsyAddress,
        address paymentTokenAddress
    ) Ownable(msg.sender) {
        require(whimsyAddress != address(0), "Factory: zero whimsy");
        require(
            paymentTokenAddress != address(0),
            "Factory: zero paymentToken"
        );
        whimsy = whimsyAddress;
        paymentToken = IERC20(paymentTokenAddress);
    }

    modifier validProperty(uint256 propertyId) {
        require(
            propertyId > 0 && propertyId <= propertyCount,
            "Factory: bad id"
        );
        require(
            properties[propertyId].token != address(0),
            "Factory: no token"
        );
        _;
    }

    function _t(uint256 pid) internal view returns (IPropertyToken) {
        return IPropertyToken(properties[pid].token);
    }

    function createIPropertyToken(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address seller,
        uint256 targetSellerOwnership,
        uint256 tokenPrice // in USDC decimals
    ) external onlyOwner whenNotPaused returns (address) {
        require(seller != address(0), "zero seller");
        require(tokenPrice > 0, "price zero");
        require(
            targetSellerOwnership >= (initialSupply * 10) / PCT_BASE &&
                targetSellerOwnership <= (initialSupply * 30) / PCT_BASE,
            "target 10 to 30%"
        );

        // 1) deploy
        PropertyToken tok = new PropertyToken(
            name,
            symbol,
            initialSupply,
            seller,
            whimsy,
            address(this),
            address(paymentToken),
            signer
        );
        // tok.setOperator(address(this));

        // 2) compute sale allocation
        uint256 whimsyAlloc = (initialSupply * WHIMSY_PCT) / PCT_BASE;
        uint256 tokensForSale = initialSupply -
            whimsyAlloc -
            targetSellerOwnership;

        // 3) configure sale
        tok.setSaleParameters(tokensForSale, tokenPrice, targetSellerOwnership);

        // 4) register & emit
        uint256 id = ++propertyCount;
        properties[id] = Property({token: address(tok), seller: seller});
        emit NewProperty(id, address(tok));

        return address(tok);
    }

    function setWhimsy(
        uint256 propertyId,
        address newWhimsy
    ) external onlyOwner {
        require(newWhimsy != address(0), "Factory: zero address");
        emit WhimsyUpdated(whimsy, newWhimsy);
        _t(propertyId).setWhimsy(newWhimsy);
    }

    function setSigner(address assignedSigner) public onlyOwner {
        signer = assignedSigner;
    }

    function setSaleParameters(
        uint256 propertyId,
        uint256 tokensForSale,
        uint256 tokenPrice,
        uint256 sellerTargetOwnership
    ) external onlyOwner whenNotPaused validProperty(propertyId) {
        IPropertyToken(properties[propertyId].token).setSaleParameters(
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

    function setTokenSigner(
        uint256 propertyId,
        address assignedSigner
    ) public onlyOwner {
        _t(propertyId).setSigner(assignedSigner);
    }

    function endSaleEarly(
        uint256 propertyId
    ) external onlyOwner whenNotPaused validProperty(propertyId) {
        _t(propertyId).endSaleEarly();
    }

    function buyTokens(
        uint256 propertyId,
        uint256 amount
    ) external whenNotPaused validProperty(propertyId) {
        address tok = properties[propertyId].token;

        // mint/transfer tokens to buyer
        IPropertyToken(tok).buyTokensFor(msg.sender, amount);
    }

    function agreeDisclaimer(
        uint256 pid
    ) external whenNotPaused validProperty(pid) {
        _t(pid).agreeDisclaimerFor(msg.sender);
    }

    function reserveTokens(
        uint256 pid,
        uint256 amount
    ) external whenNotPaused validProperty(pid) {
        // _t(pid) is your IPropertyToken
        // reservation contract will pull USDC from buyer via paymentToken.safeTransferFrom
        _t(pid).reserveTokensFor(msg.sender, amount);
    }

    function refundUnagreedBuyer(
        uint256 pid,
        address b
    ) external onlyOwner whenNotPaused validProperty(pid) {
        require(b != address(0), "Factory: zero buyer");
        _t(pid).refundUnagreedBuyer(b);
    }

    function increaseSupply(
        uint256 propertyId,
        uint256 amount
    ) external onlyOwner validProperty(propertyId) {
        IPropertyToken(properties[propertyId].token).increaseSupply(amount);
        emit SupplyIncreased(propertyId, amount);
    }

    function updateSellerAddress(
        uint256 propertyId,
        address newSeller
    ) external whenNotPaused validProperty(propertyId) {
        require(newSeller != address(0), "Factory: zero newSeller");
        Property storage p = properties[propertyId];
        if (msg.sender != p.seller && msg.sender != whimsy)
            revert Unauthorized();

        p.seller = newSeller;
        IPropertyToken(p.token).updateSellerAddress(newSeller);
        emit SellerUpdated(propertyId, newSeller);
    }

    function clawback(
        uint256 propertyId,
        address tokenOwner
    ) external onlyOwner validProperty(propertyId) {
        require(tokenOwner != address(0), "Factory: zero owner");
        IPropertyToken tok = IPropertyToken(properties[propertyId].token);
        uint256 bal = tok.balanceOf(tokenOwner);
        require(bal > 0, "Factory: no tokens");

        tok.operatorTransfer(tokenOwner, owner(), bal);
        emit Clawback(propertyId, tokenOwner, bal);
    }

    function pauseToken(
        uint256 pid
    ) external onlyOwner whenNotPaused validProperty(pid) {
        _t(pid).pause();
    }

    function unpauseToken(uint256 pid) external onlyOwner validProperty(pid) {
        _t(pid).unpause();
    }

    function toggleTokenTransfers(
        uint256 pid,
        bool e
    ) external onlyOwner validProperty(pid) {
        _t(pid).toggleTransfers(e);
    }

    function setTokenOperator(
        uint256 pid,
        address op
    ) external onlyOwner validProperty(pid) {
        _t(pid).setOperator(op);
    }

    function mintMoreSupply(
        uint256 pid,
        uint256 amt
    ) external onlyOwner validProperty(pid) {
        _t(pid).increaseSupply(amt);
    }

    function withdrawPayment(
        uint256 propertyId
    ) external onlyOwner validProperty(propertyId) {
        address tok = properties[propertyId].token;
        // ask token contract to send its balance to its seller
        IPropertyToken(tok).withdrawPayment();
    }

    function transferTokenOwnership(
        uint256 propertyId,
        address newOwner
    ) external onlyOwner validProperty(propertyId) {
        require(newOwner != address(0), "Factory: zero newOwner");
        IPropertyToken tok = IPropertyToken(properties[propertyId].token);
        address prev = tok.owner();
        tok.transferOwnership(newOwner);
        emit TokenOwnershipTransferred(propertyId, prev, newOwner);
    }

    // getters just forward to token:
    function getPostMoneyValuation(
        uint256 pid,
        uint256 pre
    ) external view validProperty(pid) returns (uint256) {
        return _t(pid).getPostMoneyValuation(pre);
    }

    function getIPropertyToken(
        uint256 pid
    ) external view validProperty(pid) returns (address) {
        return properties[pid].token;
    }

    function getSeller(
        uint256 pid
    ) external view validProperty(pid) returns (address) {
        return properties[pid].seller;
    }

    function proposalsLength(
        uint256 pid
    ) external view validProperty(pid) returns (uint256) {
        return _t(pid).proposalsLength();
    }

    function getProposal(
        uint256 pid,
        uint256 propId
    )
        external
        view
        validProperty(pid)
        returns (string memory, uint256, uint256, bool)
    {
        return _t(pid).getProposal(propId);
    }
}
