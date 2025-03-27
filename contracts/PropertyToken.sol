// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice PropertyToken implements:
 *  - An ERC20 token where all tokens are initially minted to the seller.
 *  - An immediate allocation of 3% of tokens to Whimsy.
 *  - A sale mechanism where the seller (via an operator) sets:
 *      • tokenPrice,
 *      • tokensForSale, and
 *      • a targetSellerOwnership (the seller’s balance after sale) which must be between 10% and 30% of total supply.
 *  - A buyTokens function that enforces:
 *      • Buyers cannot hold more than 15% of total supply,
 *      • The seller’s balance never drops below the target,
 *      • Correct ETH is sent.
 *  - A transfer toggle and a function to update the seller address.
 *  - A DAO-controlled supply increase.
 */
contract PropertyToken is ERC20, Ownable {
    // The property owner (seller)
    address public seller;
    // The designated operator (admin) contract address
    address public operator;
    // Transfer toggling flag
    bool public transfersEnabled = true;

    // Sale parameters:
    // tokenPrice is the cost per token (in wei)
    uint256 public tokenPrice;
    // tokensForSale is the number of tokens allocated for sale.
    uint256 public tokensForSale;
    // targetSellerOwnership is the desired seller balance after the sale.
    // It must be between 10% and 30% of total supply.
    uint256 public targetSellerOwnership;

    // Buyer limit: any buyer (non-seller) cannot hold more than 15% of the total supply.
    uint256 public constant MAX_BUYER_PERCENT = 15;

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
    event SupplyIncreased(uint256 additionalTokens);
    event SellerAddressUpdated(address oldSeller, address newSeller);

    /**
     * @param name_         Token name.
     * @param symbol_       Token symbol.
     * @param initialSupply_ Total initial supply.
     * @param seller_       The property owner address.
     * @param whimsyAddress The address that receives 3% of tokens immediately.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_,
        address seller_,
        address whimsyAddress
    ) ERC20(name_, symbol_) Ownable(seller_) {
        require(seller_ != address(0), "Invalid seller address");
        seller = seller_;
        // Mint the entire initial supply to the seller.
        _mint(seller, initialSupply_);
        // Immediately allocate 3% of tokens to Whimsy.
        uint256 whimsyAllocation = (initialSupply_ * 3) / 100;
        _transfer(seller, whimsyAddress, whimsyAllocation);
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "Not authorized: operator only");
        _;
    }

    /**
     * @notice Sets the operator contract address.
     */
    function setOperator(address newOperator) external onlyOwner {
        require(newOperator != address(0), "Invalid operator address");
        emit OperatorUpdated(operator, newOperator);
        operator = newOperator;
    }

    /**
     * @notice Toggles transfers on or off.
     */
    function toggleTransfers(bool enabled) external onlyOwner {
        transfersEnabled = enabled;
        emit TransfersToggled(enabled);
    }

    /**
     * @notice Sets sale parameters.
     * @param _tokensForSale        The number of tokens the seller intends to sell.
     * @param _tokenPrice           Price per token (in wei).
     * @param _targetSellerOwnership The seller's balance after the sale.
     *
     * Requirements:
     * - _targetSellerOwnership must be between 10% and 30% of total supply.
     * - The tokens for sale must exactly equal the seller's current balance minus the target.
     */
    function setSaleParameters(
        uint256 _tokensForSale,
        uint256 _tokenPrice,
        uint256 _targetSellerOwnership
    ) external onlyOperator {
        uint256 total = totalSupply();
        require(
            _targetSellerOwnership >= (total * 10) / 100,
            "Target ownership below 10% of total supply"
        );
        require(
            _targetSellerOwnership <= (total * 30) / 100,
            "Target ownership above 30% of total supply"
        );
        require(
            balanceOf(seller) >= _tokensForSale,
            "Seller balance insufficient"
        );
        require(
            balanceOf(seller) - _tokensForSale == _targetSellerOwnership,
            "Sale tokens must equal seller balance minus target ownership"
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

    /**
     * @notice Allows buyers to purchase tokens.
     * Buyers must send exactly (amount * tokenPrice) in ETH.
     * Enforces:
     *  - The buyer's balance after purchase cannot exceed 15% of total supply.
     *  - The seller's balance after purchase does not drop below the targetSellerOwnership.
     */
    function buyTokens(uint256 amount) external payable {
        require(amount > 0, "Amount must be > 0");
        require(
            amount <= tokensForSale,
            "Not enough tokens available for sale"
        );
        require(msg.value == amount * tokenPrice, "Incorrect ETH sent");
        require(
            balanceOf(msg.sender) + amount <=
                (totalSupply() * MAX_BUYER_PERCENT) / 100,
            "Buyer would exceed 15% of total supply"
        );
        require(
            balanceOf(seller) - amount >= targetSellerOwnership,
            "Seller cannot drop below target ownership"
        );

        tokensForSale -= amount;
        _transfer(seller, msg.sender, amount);
    }

    /**
     * @notice Updates the seller address (in case the property owner wants to transfer their wallet).
     */
    function updateSellerAddress(address newSeller) external onlyOwner {
        require(newSeller != address(0), "Invalid address");
        emit SellerAddressUpdated(seller, newSeller);
        seller = newSeller;
    }

    /**
     * @notice Increases the token supply.
     * Mints additional tokens to the seller. (DAO-controlled via the operator.)
     */
    function increaseSupply(uint256 additionalTokens) external onlyOperator {
        _mint(seller, additionalTokens);
        emit SupplyIncreased(additionalTokens);
    }

    /**
     * @notice Override _beforeTokenTransfer to enforce transfer rules.
     * - Transfers are only allowed when enabled.
     * - When seller transfers tokens (i.e. in a sale), their balance must not drop below targetSellerOwnership.
     * - For any non-seller recipient, the resulting balance must not exceed 15% of total supply.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(transfersEnabled, "Transfers are disabled");

        if (from == seller && from != address(0)) {
            uint256 sellerBalanceAfter = balanceOf(seller) - amount;
            require(
                sellerBalanceAfter >= targetSellerOwnership,
                "Seller must retain target ownership"
            );
        }

        if (to != seller && to != address(0)) {
            require(
                balanceOf(to) + amount <=
                    (totalSupply() * MAX_BUYER_PERCENT) / 100,
                "Recipient cannot exceed 15% of total supply"
            );
        }
    }

    /**
     * @notice Computes the post-money (fully diluted) valuation.
     * Funds raised is calculated as: (tokens sold × tokenPrice).
     * For example, if the property is valued at $300k pre-money and $50k is raised, FDV = $350k.
     */
    function getPostMoneyValuation(uint256 preMoneyValuation)
        external
        view
        returns (uint256)
    {
        // tokensSold = initial seller balance (at sale start) minus current seller balance.
        uint256 sold = (balanceOf(seller) + tokensForSale) -
            targetSellerOwnership;
        uint256 fundsRaised = sold * tokenPrice;
        return preMoneyValuation + fundsRaised;
    }
}
