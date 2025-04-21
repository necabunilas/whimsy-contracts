// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWhimsyOffering is IERC20 {
    function assignClaimList(
        address[] calldata claimers,
        uint256[] calldata claimAmounts
    ) external;

    function setRequireSignatureOnTransfer(bool isRequire) external;
    function setSigner(address assignedSigner) external;
    function operatorClaim(address claimer) external;
    function operatorTransfer(address from, address to, uint256 value) external;
    function claimList(address claimer) external view returns (uint256);
}
