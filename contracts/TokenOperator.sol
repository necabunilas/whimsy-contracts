// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./PropertyToken.sol";

/**
 * @notice TokenOperator acts as an administrator for the PropertyToken.
 * It allows the owner (DAO or project admin) to:
 *  - Set sale parameters.
 *  - Increase token supply.
 *  - Toggle transfers.
 */
contract TokenOperator is Ownable {
    PropertyToken public tokenContract;

    event SaleParametersSet(uint256 tokensForSale, uint256 tokenPrice, uint256 targetSellerOwnership);
    event SupplyIncreased(uint256 additionalTokens);

    constructor(PropertyToken _tokenContract) Ownable(msg.sender) {
        tokenContract = _tokenContract;
    }

    /**
     * @notice Sets sale parameters on the token contract.
     */
    function setSaleParameters(
        uint256 tokensForSale,
        uint256 tokenPrice,
        uint256 targetSellerOwnership
    ) external onlyOwner {
        tokenContract.setSaleParameters(tokensForSale, tokenPrice, targetSellerOwnership);
        emit SaleParametersSet(tokensForSale, tokenPrice, targetSellerOwnership);
    }

    /**
     * @notice Increases the token supply via the token contract.
     */
    function increaseSupply(uint256 additionalTokens) external onlyOwner {
        tokenContract.increaseSupply(additionalTokens);
        emit SupplyIncreased(additionalTokens);
    }

    /**
     * @notice Toggles token transfers by calling the token contract's toggle function.
     */
    function toggleTransfers(bool enabled) external onlyOwner {
        tokenContract.toggleTransfers(enabled);
    }
}
