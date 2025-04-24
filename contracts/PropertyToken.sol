// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract PropertyToken is ERC20, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    IERC20 public immutable paymentToken;

    bool public requireSignatureOnTransfer = true;
    mapping(bytes32 => bool) public bufferUsed;

    address public seller;
    address public operator;
    address public factory;
    address public governanceContract;
    address public whimsy;
    bool public saleEnded = false;

    bool public transfersEnabled = true;

    uint256 public tokenPrice;
    uint256 public tokensForSale;
    uint256 public targetSellerOwnership;
    uint256 public totalRaised;
    uint256 public totalReserved;
    uint256 public saleSupplySnapshot;
    address private signer;
    uint8 public paymentTokenDecimals;

    uint8 public constant PERCENT_BASE = 100;
    uint8 public constant WHIMSY_ALLOCATION_PERCENT = 3;
    uint8 public constant SELLER_ALLOCATION_PERCENT =
        PERCENT_BASE - WHIMSY_ALLOCATION_PERCENT;
    uint8 public constant MIN_SELLER_PERCENT = 10;
    uint8 public constant MAX_SELLER_PERCENT = 30;
    uint8 public constant MAX_BUYER_PERCENT = 15;

    uint256 public constant AGREEMENT_TIMEOUT = 5 days;

    struct Reservation {
        uint256 amount;
        uint256 timestamp;
    }

    mapping(address => bool) public hasAgreedDisclaimer;
    mapping(address => Reservation) public pendingReservations;

    event OperatorUpdated(
        address indexed oldOperator,
        address indexed newOperator
    );
    event TransfersToggled(bool enabled);
    event SaleParametersUpdated(
        uint256 tokensForSale,
        uint256 tokenPrice,
        uint256 targetSellerOwnership
    );
    event TokensPurchased(address indexed buyer, uint256 amount);
    event SupplyIncreased(uint256 additionalTokens);
    event SellerAddressUpdated(address oldSeller, address newSeller);
    event Withdrawn(uint256 amount, address to);
    event DisclaimerAgreed(address indexed buyer);
    event RefundIssued(address indexed buyer, uint256 amount);
    event WhimsyUpdated(address indexed oldWhimsy, address indexed newWhimsy);
    event SaleEndedEarly();
    event SignatureTransfer(
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes32 buffer
    );
    event ETHWithdrawn(uint256 amount, address to);

    modifier onlyOperator() {
        require(msg.sender == operator, "Not authorized: operator only");
        _;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_,
        address seller_,
        address whimsyAddress,
        address owner_,
        address paymentTokenAddress,
        address assignedSigner
    ) ERC20(name_, symbol_) Ownable(owner_) {
        require(seller_ != address(0), "Invalid seller");
        require(whimsyAddress != address(0), "Invalid whimsy");
        require(paymentTokenAddress != address(0), "Invalid paymentToken");

        whimsy = whimsyAddress;
        seller = seller_;
        factory = owner_;
        paymentToken = IERC20(paymentTokenAddress);
        signer = assignedSigner;
        paymentTokenDecimals = IERC20Metadata(paymentTokenAddress).decimals();
        // mint the initial split
        uint256 whimsyAlloc = (initialSupply_ * WHIMSY_ALLOCATION_PERCENT) /
            PERCENT_BASE;
        uint256 sellerAlloc = initialSupply_ - whimsyAlloc;
        _mint(seller_, sellerAlloc);
        _mint(whimsyAddress, whimsyAlloc);
    }

    function decimals() public view override returns (uint8) {
        return paymentTokenDecimals;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setWhimsy(address newWhimsy) external onlyOwner {
        require(newWhimsy != address(0), "Invalid address");
        emit WhimsyUpdated(whimsy, newWhimsy);
        whimsy = newWhimsy;
    }

    function setRequireSignatureOnTransfer(bool on) external onlyOwner {
        requireSignatureOnTransfer = on;
    }

    function setOperator(address newOperator) external onlyOwner {
        require(newOperator != address(0), "Invalid operator");
        operator = newOperator;
        emit OperatorUpdated(operator, newOperator);
    }

    function setFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "Factory cannot be zero address");
        factory = _factory;
    }

    function setSigner(address assignedSigner) public onlyOwner {
        require(assignedSigner != address(0), "Signer cannot be zero address");
        signer = assignedSigner;
    }

    function toggleTransfers(bool enabled) external onlyOwner {
        transfersEnabled = enabled;
        emit TransfersToggled(enabled);
    }

    function updateSellerAddress(address newSeller) external onlyOwner {
        require(newSeller != address(0), "Invalid seller");
        emit SellerAddressUpdated(seller, newSeller);
        seller = newSeller;
    }

    function increaseSupply(uint256 amount) external onlyOwner {
        require(tokensForSale == 0, "Can't mint during sale");
        _mint(seller, amount);
        emit SupplyIncreased(amount);
    }

    function withdrawPayment() external nonReentrant whenNotPaused {
        require(
            msg.sender == owner() || msg.sender == operator,
            "Not authorized"
        );
        require(saleEnded, "Cannot withdraw during sale");
        uint256 bal = paymentToken.balanceOf(address(this));
        require(bal > 0, "No funds to withdraw");
        paymentToken.safeTransfer(seller, bal);
        emit Withdrawn(bal, seller);
    }

    function setSaleParameters(
        uint256 _tokensForSale,
        uint256 _tokenPrice,
        uint256 _targetSellerOwnership
    ) external onlyOwner whenNotPaused {
        require(_tokenPrice > 0, "Token price > 0");

        uint256 currentTotal = totalSupply();
        saleSupplySnapshot = currentTotal;

        require(
            _targetSellerOwnership >=
                (currentTotal * MIN_SELLER_PERCENT) / PERCENT_BASE,
            "Target >= 10%"
        );
        require(
            _targetSellerOwnership <=
                (currentTotal * MAX_SELLER_PERCENT) / PERCENT_BASE,
            "Target <= 30%"
        );
        require(balanceOf(seller) >= _tokensForSale, "Seller bal low");
        require(
            balanceOf(seller) - _tokensForSale == _targetSellerOwnership,
            "Bad sale/tgt split"
        );

        tokensForSale = _tokensForSale;
        tokenPrice = _tokenPrice;
        targetSellerOwnership = _targetSellerOwnership;

        emit SaleParametersUpdated(
            _tokensForSale,
            _tokenPrice,
            _targetSellerOwnership
        );
    }

    function agreeDisclaimerFor(address buyer) external onlyFactory {
        hasAgreedDisclaimer[buyer] = true;
        emit DisclaimerAgreed(buyer);
    }

    function reserveTokensFor(
        address buyer,
        uint256 amount
    ) external onlyFactory {
        require(amount > 0, "Amount>0");
        require(pendingReservations[buyer].amount == 0, "Already reserved");
        require(amount <= tokensForSale - totalReserved, "Exceeds sale");

        // pull paymentToken in advance
        uint256 cost = (amount * tokenPrice) / (10 ** decimals());
        paymentToken.safeTransferFrom(buyer, address(this), cost);

        pendingReservations[buyer] = Reservation(amount, block.timestamp);
        totalReserved += amount;
    }

    function refundUnagreedBuyer(
        address buyer
    ) external onlyOwner whenNotPaused nonReentrant {
        Reservation memory r = pendingReservations[buyer];
        require(r.amount > 0, "No reservation");
        require(!hasAgreedDisclaimer[buyer], "Already agreed");
        require(
            block.timestamp >= r.timestamp + AGREEMENT_TIMEOUT,
            "Too early"
        );

        totalReserved -= r.amount;
        delete pendingReservations[buyer];

        uint256 cost = (r.amount * tokenPrice) / (10 ** decimals());
        paymentToken.safeTransfer(buyer, cost);
        emit RefundIssued(buyer, r.amount);
    }

    function endSaleEarly() external onlyOwner whenNotPaused {
        require(!saleEnded, "Sale already ended");
        saleEnded = true;
        tokensForSale = 0; // Optional: disable any further token purchases
        emit SaleEndedEarly();
    }

    function buyTokensFor(
        address buyer,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyFactory {
        require(!saleEnded, "Sale has ended");
        require(hasAgreedDisclaimer[buyer], "Disclaim first");
        require(amount > 0, "Amount>0");

        uint256 cost = (amount * tokenPrice) / (10 ** decimals());

        Reservation memory r = pendingReservations[buyer];
        if (r.amount > 0) {
            require(amount == r.amount, "Must buy reserved");

            totalReserved -= amount;
            delete pendingReservations[buyer];
            // cost already paid in reserveTokensFor
        } else {
            require(amount <= tokensForSale - totalReserved, "Exceeds sale");
            paymentToken.safeTransferFrom(buyer, address(this), cost);
        }

        tokensForSale -= amount;
        totalRaised += cost;

        _transfer(seller, buyer, amount);
        emit TokensPurchased(buyer, amount);
    }

    function getPostMoneyValuation(
        uint256 preMoneyValuation
    ) external view returns (uint256) {
        return preMoneyValuation + totalRaised;
    }

    function operatorTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyOwner whenNotPaused {
        require(from != address(0), "operatorTransfer: from zero address");
        require(to != address(0), "operatorTransfer: to zero address");
        _transfer(from, to, amount);
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        _beforeTokenTransfer(from, to, amount);
        super._update(from, to, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal view {
        require(
            transfersEnabled || from == address(0) || to == address(0),
            "Transfers are disabled"
        );

        if (from != address(0) && to != address(0)) {
            if (from == seller) {
                uint256 afterBalance = balanceOf(seller) - amount;
                require(
                    afterBalance >= targetSellerOwnership,
                    "Seller must retain minimum ownership"
                );
            }

            if (to != seller) {
                uint256 snapshot = saleSupplySnapshot == 0
                    ? totalSupply()
                    : saleSupplySnapshot;
                require(
                    balanceOf(to) + amount <=
                        (snapshot * MAX_BUYER_PERCENT) / PERCENT_BASE,
                    "Buyer exceeds 15% cap"
                );
            }
        }
    }

    function withdrawETH() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "No ETH to withdraw");
        (bool success, ) = payable(seller).call{value: bal}("");
        require(success, "ETH transfer failed");
        emit ETHWithdrawn(bal, seller);
    }

    function signatureTransfer(
        bytes32 buffer,
        bytes calldata sig,
        address to,
        uint256 amount
    ) external whenNotPaused returns (bool) {
        // 1) make sure this buffer hasn’t been used
        require(!bufferUsed[buffer], "Buffer replay");
        bufferUsed[buffer] = true;

        // 2) re‑compute the message
        bytes32 h = keccak256(abi.encodePacked(buffer, msg.sender, to, amount));
        // 3) prefix it & recover
        bytes32 ethMsg = MessageHashUtils.toEthSignedMessageHash(h);
        address recovered = ethMsg.recover(sig);
        require(recovered == signer, "Invalid signature");

        // 4) do the transfer
        _transfer(msg.sender, to, amount);
        emit SignatureTransfer(msg.sender, to, amount, buffer);
        return true;
    }

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        if (requireSignatureOnTransfer) revert("Direct transfers disabled");
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        if (requireSignatureOnTransfer) revert("Direct transfers disabled");
        return super.transferFrom(from, to, amount);
    }

    receive() external payable {
        revert("ETH not accepted");
    }

    fallback() external payable {
        revert("ETH not accepted");
    }
}
