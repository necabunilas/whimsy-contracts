// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PropertyToken is ERC20, Ownable {
    address public seller;
    address public operator;

    bool public transfersEnabled = true;

    uint256 public tokenPrice;
    uint256 public tokensForSale;
    uint256 public targetSellerOwnership;
    uint256 public totalRaised;

    uint256 public constant MAX_BUYER_PERCENT = 15;
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

    // Governance
    event ProposalCreated(uint256 indexed proposalId, string description);
    event Voted(
        uint256 indexed proposalId,
        address voter,
        bool support,
        uint256 weight
    );
    event ProposalFinalized(uint256 indexed proposalId, bool passed);

    modifier onlyOperator() {
        require(msg.sender == operator, "Not authorized: operator only");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_,
        address seller_,
        address whimsyAddress
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        require(seller_ != address(0), "Invalid seller address");
        require(whimsyAddress != address(0), "Invalid whimsy address");

        seller = seller_;

        uint256 whimsyAllocation = (initialSupply_ * 3) / 100;
        uint256 sellerAllocation = initialSupply_ - whimsyAllocation;

        // Mint 97% directly to seller
        _mint(seller_, sellerAllocation);

        // Mint 3% directly to Whimsy
        _mint(whimsyAddress, whimsyAllocation);
    }

    // ===== Admin Functions =====

    function setOperator(address newOperator) external onlyOwner {
        require(newOperator != address(0), "Invalid operator address");
        emit OperatorUpdated(operator, newOperator);
        operator = newOperator;
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
        _mint(seller, amount);
        emit SupplyIncreased(amount);
    }

    function withdraw() external {
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

    // ===== Sale Management =====

    function setSaleParameters(
        uint256 _tokensForSale,
        uint256 _tokenPrice,
        uint256 _targetSellerOwnership
    ) external onlyOperator {
        uint256 total = totalSupply();

        require(_targetSellerOwnership >= (total * 10) / 100, "Target < 10%");
        require(_targetSellerOwnership <= (total * 30) / 100, "Target > 30%");
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

    function agreeDisclaimer() external {
        hasAgreedDisclaimer[msg.sender] = true;
        emit DisclaimerAgreed(msg.sender);
    }

    function reserveTokens(uint256 amount) external payable {
        require(amount > 0, "Amount must be > 0");
        require(
            pendingReservations[msg.sender].amount == 0,
            "Reservation exists"
        );
        require(msg.value == amount * tokenPrice, "Incorrect ETH sent");

        pendingReservations[msg.sender] = Reservation({
            amount: amount,
            timestamp: block.timestamp
        });
    }

    function refundUnagreedBuyer(address buyer) external onlyOperator {
        Reservation memory res = pendingReservations[buyer];
        require(res.amount > 0, "No reservation");
        require(!hasAgreedDisclaimer[buyer], "Buyer already agreed");
        require(
            block.timestamp >= res.timestamp + AGREEMENT_TIMEOUT,
            "Timeout not reached"
        );

        // Do not adjust tokensForSale – the reservation did not reduce it.
        delete pendingReservations[buyer];

        (bool success, ) = payable(buyer).call{value: res.amount * tokenPrice}(
            ""
        );
        require(success, "Refund failed");

        emit RefundIssued(buyer, res.amount);
    }

    function buyTokens(uint256 amount) external payable {
        require(
            hasAgreedDisclaimer[msg.sender],
            "Must agree to disclaimer first"
        );
        require(amount > 0, "Amount must be > 0");
        require(amount <= tokensForSale, "Not enough tokens for sale");
        require(msg.value == amount * tokenPrice, "Incorrect ETH sent");

        require(
            balanceOf(msg.sender) + amount <=
                (totalSupply() * MAX_BUYER_PERCENT) / 100,
            "Buyer exceeds 15% cap"
        );
        require(
            balanceOf(seller) - amount >= targetSellerOwnership,
            "Seller would go below target"
        );

        tokensForSale -= amount;
        totalRaised += msg.value;

        _transfer(seller, msg.sender, amount);

        delete pendingReservations[msg.sender];

        emit TokensPurchased(msg.sender, amount);
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
    ) external onlyOperator {
        _transfer(from, to, amount);
    }

    // ===== Transfer Hook =====
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
        if (from == address(0) || to == address(0)) return;
        require(transfersEnabled, "Transfers are disabled");

        if (from == seller) {
            uint256 afterBalance = balanceOf(seller) - amount;
            require(
                afterBalance >= targetSellerOwnership,
                "Seller must retain minimum ownership"
            );
        }

        if (to != seller) {
            require(
                balanceOf(to) + amount <=
                    (totalSupply() * MAX_BUYER_PERCENT) / 100,
                "Recipient exceeds 15% cap"
            );
        }
    }

    // ===== Governance =====

    struct Proposal {
        string description;
        uint256 yesVotes;
        uint256 noVotes;
        bool finalized;
        mapping(address => bool) hasVoted;
    }

    Proposal[] private _proposals;

    function createProposal(string memory description) external onlyOperator {
        Proposal storage newProposal = _proposals.push();
        newProposal.description = description;
        emit ProposalCreated(_proposals.length - 1, description);
    }

    function vote(uint256 proposalId, bool support) external {
        Proposal storage p = _proposals[proposalId];
        require(!p.finalized, "Proposal finalized");
        require(!p.hasVoted[msg.sender], "Already voted");

        uint256 weight = balanceOf(msg.sender);
        require(weight > 0, "No voting power");

        if (support) {
            p.yesVotes += weight;
        } else {
            p.noVotes += weight;
        }

        p.hasVoted[msg.sender] = true;
        emit Voted(proposalId, msg.sender, support, weight);
    }

    function finalizeProposal(uint256 proposalId) external onlyOperator {
        Proposal storage p = _proposals[proposalId];
        require(!p.finalized, "Already finalized");

        p.finalized = true;
        bool passed = p.yesVotes > p.noVotes;
        emit ProposalFinalized(proposalId, passed);
    }

    function getProposal(
        uint256 proposalId
    )
        external
        view
        returns (
            string memory description,
            uint256 yesVotes,
            uint256 noVotes,
            bool finalized
        )
    {
        Proposal storage p = _proposals[proposalId];
        return (p.description, p.yesVotes, p.noVotes, p.finalized);
    }

    function proposalsLength() external view returns (uint256) {
        return _proposals.length;
    }

    receive() external payable {}

    fallback() external payable {}
}

//factory property token from whimsy - done
//token operator only one for all tokens - done
//no need to redeploy for factory - done
//gawa ng interface to include
//check onlyOwner
//add withdraw
//transfers enabled
//after mint set false transfer enabled
//_update super._update
//address(0) is mint and burn
// add property for property value
//increase tokensold in buy
//in property value
//try using amount raised
//is withdrawal once or per transaction?

//wei amount
//add clawback
