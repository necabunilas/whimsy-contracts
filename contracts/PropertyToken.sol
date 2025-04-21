// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./PropertyGovernance.sol";


contract PropertyToken is ERC20, Ownable, ReentrancyGuard, Pausable, PropertyTokenGovernance {
    address public seller;
    address public operator;
    address public factory;

    bool public transfersEnabled = true;

    uint256 public tokenPrice;
    uint256 public tokensForSale;
    uint256 public targetSellerOwnership;
    uint256 public totalRaised;
    uint256 public totalReserved;
    uint256 public saleSupplySnapshot;

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
        address owner_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        require(seller_ != address(0), "Invalid seller");
        require(whimsyAddress != address(0), "Invalid whimsy");

        seller = seller_;
        factory = owner_;


        uint256 whimsyAllocation = (initialSupply_ *
            WHIMSY_ALLOCATION_PERCENT) / PERCENT_BASE;
        uint256 sellerAllocation = (initialSupply_ *
            SELLER_ALLOCATION_PERCENT) / PERCENT_BASE;

        _mint(seller_, sellerAllocation);
        _mint(whimsyAddress, whimsyAllocation);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }


    function setOperator(address newOperator) external onlyOwner {
        require(newOperator != address(0), "Invalid operator address");
        emit OperatorUpdated(operator, newOperator);
        operator = newOperator;
    }

    function setFactory(address _factory) external onlyOwner {
        require(factory == address(0), "Factory already set");
        factory = _factory;
    }

    function toggleTransfers(bool enabled) external onlyOwner {
        transfersEnabled = enabled;
        emit TransfersToggled(enabled);
    }

    function updateSellerAddress(address newSeller) external onlyOwner {
        require(newSeller != address(0), "Invalid address");
        emit SellerAddressUpdated(seller, newSeller);
        seller = newSeller;
    }

    function increaseSupply(uint256 amount) external onlyOwner {
        require(tokensForSale == 0, "Can't mint during active sale");
        _mint(seller, amount);
        emit SupplyIncreased(amount);
    }

    function withdraw() external nonReentrant whenNotPaused {
        require(
            msg.sender == owner() || msg.sender == operator,
            "Not authorized"
        );
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");

        (bool sent, ) = payable(seller).call{value: balance}("");
        require(sent, "Withdraw failed");

        emit Withdrawn(balance, seller);
    }


    function setSaleParameters(
        uint256 _tokensForSale,
        uint256 _tokenPrice,
        uint256 _targetSellerOwnership
    ) external onlyOperator whenNotPaused {
        require(_tokenPrice > 0, "Token price must be > 0");

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

        require(balanceOf(seller) >= _tokensForSale, "Seller balance low");
        require(
            balanceOf(seller) - _tokensForSale == _targetSellerOwnership,
            "tokensForSale must equal seller balance minus target"
        );

        tokenPrice = _tokenPrice;
        tokensForSale = _tokensForSale;
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
    ) external payable onlyFactory {
        require(msg.value == amount * tokenPrice, "Incorrect ETH sent");
        require(amount > 0, "Amount must be > 0");
        require(pendingReservations[buyer].amount == 0, "Reservation exists");
        
        require(
            amount <= tokensForSale - totalReserved,
            "Not enough tokens left"
        );

        require(msg.value == amount * tokenPrice, "Incorrect ETH sent");

        pendingReservations[buyer] = Reservation({
            amount: amount,
            timestamp: block.timestamp
        });
        totalReserved += amount;
    }

    function refundUnagreedBuyer(
        address buyer
    ) external onlyOperator whenNotPaused nonReentrant {
        require(buyer != address(0), "refundUnagreedBuyer: zero address");
        Reservation memory res = pendingReservations[buyer];
        require(res.amount > 0, "No reservation");
        require(!hasAgreedDisclaimer[buyer], "Buyer already agreed");
        require(
            block.timestamp >= res.timestamp + AGREEMENT_TIMEOUT,
            "Timeout not reached"
        );

        totalReserved -= res.amount;
        delete pendingReservations[buyer];

        (bool success, ) = payable(buyer).call{value: res.amount * tokenPrice}(
            ""
        );
        require(success, "Refund failed");

        emit RefundIssued(buyer, res.amount);
    }

    function buyTokensFor(
        address buyer,
        uint256 amount
    ) external payable whenNotPaused nonReentrant onlyFactory {
        require(hasAgreedDisclaimer[buyer], "Must agree to disclaimer first");
        require(amount > 0, "Amount must be > 0");

        Reservation memory res = pendingReservations[buyer];
        if (res.amount > 0) {
            require(amount == res.amount, "Must buy reserved amount");
            require(msg.value == 0, "No extra ETH");

            totalReserved -= amount;
            delete pendingReservations[buyer];

            tokensForSale -= amount;
            totalRaised += amount * tokenPrice;
        } else {
            require(amount <= tokensForSale - totalReserved, "Not enough left");
            require(msg.value == amount * tokenPrice, "Incorrect ETH sent");

            tokensForSale -= amount;
            totalRaised += msg.value;
        }

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
    ) external onlyOperator whenNotPaused {
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

    Proposal[] private _proposals;

    function createProposal(string memory description)
        public
        override
        onlyOperator
    {
        super.createProposal(description);
    }

    function voteFor(
        address voter,
        uint256 proposalId,
        bool support
    ) public override onlyOperator {
        super.voteFor(voter, proposalId, support);
    }

    function finalizeProposal(uint256 proposalId)
        public
        override
        onlyOperator
    {
        super.finalizeProposal(proposalId);
    }

    function getProposal(
        uint256 proposalId
    )
        public
        view
        override
        returns (
            string memory description,
            uint256 yesVotes,
            uint256 noVotes,
            bool finalized
        )
    {
        return super.getProposal(proposalId);
    }

    function proposalsLength() public view override returns (uint256) {
        return super.proposalsLength();
    }

    receive() external payable {}

    fallback() external payable {}
}
