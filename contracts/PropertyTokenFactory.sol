// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IPropertyToken.sol";
import "./PropertyToken.sol";

error Unauthorized();

contract PropertyTokenFactory is Ownable, Pausable {
    struct Property { address token; address seller; }
    mapping(uint256 => Property) public properties;
    uint256 public propertyCount;
    address public immutable whimsy;

    event NewProperty(uint256 indexed propertyId, address tokenAddress);
    event SellerUpdated(uint256 indexed propertyId, address newSeller);
    event Clawback(uint256 indexed propertyId, address indexed tokenOwner, uint256 amount);
    event TokenOwnershipTransferred(uint256 indexed propertyId, address indexed previousOwner, address indexed newOwner);

    constructor(address whimsyAddress) Ownable(msg.sender) {
        require(whimsyAddress != address(0), "Factory: zero whimsy");
        whimsy = whimsyAddress;
    }

    modifier validProperty(uint256 pid) {
        require(pid > 0 && pid <= propertyCount, "Factory: bad id");
        _;
    }

    /// @dev helper to reduce bytecode
    function _t(uint256 pid) internal view returns (IPropertyToken) {
        return IPropertyToken(properties[pid].token);
    }

    function createIPropertyToken(
        string memory name,
        string memory symbol,
        uint256   initialSupply,
        address   seller_
    ) external onlyOwner returns (address tok) {
        require(seller_ != address(0), "Factory: zero seller");
        tok = address(new PropertyToken(
            name, symbol, initialSupply, seller_, whimsy, address(this)
        ));
        IPropertyToken(tok).setOperator(address(this));
        properties[++propertyCount] = Property(tok, seller_);
        emit NewProperty(propertyCount, tok);
    }

    function setSaleParameters(
        uint256 pid,
        uint256 forSale,
        uint256 price,
        uint256 target
    ) external onlyOwner whenNotPaused validProperty(pid) {
        _t(pid).setSaleParameters(forSale, price, target);
        // token itself emits SaleParametersUpdated
    }

    function buyTokens(uint256 pid, uint256 amount)
      external payable whenNotPaused validProperty(pid)
    {
        _t(pid).buyTokensFor{value: msg.value}(msg.sender, amount);
    }

    function agreeDisclaimer(uint256 pid)
      external whenNotPaused validProperty(pid)
    {
        _t(pid).agreeDisclaimerFor(msg.sender);
    }

    function reserveTokens(uint256 pid, uint256 amount)
      external payable whenNotPaused validProperty(pid)
    {
        _t(pid).reserveTokensFor{value: msg.value}(msg.sender, amount);
    }

    function refundUnagreedBuyer(uint256 pid, address b)
      external onlyOwner whenNotPaused validProperty(pid)
    {
        require(b != address(0), "Factory: zero buyer");
        _t(pid).refundUnagreedBuyer(b);
    }

    function increaseSupply(uint256 pid, uint256 amt)
      external onlyOwner validProperty(pid)
    {
        _t(pid).increaseSupply(amt);
    }

    function updateSellerAddress(uint256 pid, address newSeller)
      external validProperty(pid)
    {
        require(newSeller != address(0), "Factory: zero newSeller");
        Property storage p = properties[pid];
        if (msg.sender != p.seller && msg.sender != whimsy) revert Unauthorized();
        p.seller = newSeller;
        _t(pid).updateSellerAddress(newSeller);
        emit SellerUpdated(pid, newSeller);
    }

    function clawback(uint256 pid, address who)
      external onlyOwner validProperty(pid)
    {
        require(who != address(0), "Factory: zero owner");
        IPropertyToken tok = _t(pid);
        uint256 bal = tok.balanceOf(who);
        require(bal > 0, "Factory: no tokens");
        tok.operatorTransfer(who, owner(), bal);
        emit Clawback(pid, who, bal);
    }

    function pauseToken(uint256 pid) external onlyOwner whenNotPaused validProperty(pid) {
        _t(pid).pause();
    }
    function unpauseToken(uint256 pid) external onlyOwner validProperty(pid) {
        _t(pid).unpause();
    }
    function toggleTokenTransfers(uint256 pid, bool e) external onlyOwner validProperty(pid) {
        _t(pid).toggleTransfers(e);
    }
    function setTokenOperator(uint256 pid, address op) external onlyOwner validProperty(pid) {
        _t(pid).setOperator(op);
    }
    function mintMoreSupply(uint256 pid, uint256 amt)   external onlyOwner validProperty(pid) {
        _t(pid).increaseSupply(amt);
    }
    function withdrawETHFromToken(uint256 pid)
      external onlyOwner validProperty(pid)
    {
        _t(pid).withdraw();
    }
    function transferTokenOwnership(uint256 pid, address newOwner)
      external onlyOwner validProperty(pid)
    {
        require(newOwner != address(0), "Factory: zero newOwner");
        IPropertyToken tok = _t(pid);
        address prev = tok.owner();
        tok.transferOwnership(newOwner);
        emit TokenOwnershipTransferred(pid, prev, newOwner);
    }

    function createProposal(uint256 pid, string calldata desc)
      external onlyOwner validProperty(pid)
    {
        _t(pid).createProposal(desc);
    }
    function vote(uint256 pid, uint256 propId, bool support)
      external validProperty(pid)
    {
        _t(pid).voteFor(msg.sender, propId, support);
    }
    function finalizeProposal(uint256 pid, uint256 propId)
      external onlyOwner validProperty(pid)
    {
        _t(pid).finalizeProposal(propId);
    }

    // getters just forward to token:
    function getPostMoneyValuation(uint256 pid, uint256 pre)
      external view validProperty(pid) returns (uint256)
    {
        return _t(pid).getPostMoneyValuation(pre);
    }
    function getIPropertyToken(uint256 pid)
      external view validProperty(pid) returns (address)
    {
        return properties[pid].token;
    }
    function getSeller(uint256 pid)
      external view validProperty(pid) returns (address)
    {
        return properties[pid].seller;
    }
    function proposalsLength(uint256 pid)
      external view validProperty(pid) returns (uint256)
    {
        return _t(pid).proposalsLength();
    }
    function getProposal(uint256 pid, uint256 propId)
      external view validProperty(pid)
      returns (string memory, uint256, uint256, bool)
    {
        return _t(pid).getProposal(propId);
    }
}
