// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract PropertyGovernance {
    struct Proposal {
        string description;
        uint256 yesVotes;
        uint256 noVotes;
        bool finalized;
        mapping(address => bool) hasVoted;
    }

    mapping(address => bool) public operators;
    mapping(address => bool) public registeredTokens;

    // token => proposals
    mapping(address => Proposal[]) internal _proposals;

    modifier onlyOperator(address token) {
        require(operators[msg.sender] || msg.sender == token, "Not authorized");
        require(registeredTokens[token], "Token not registered");
        _;
    }

    function registerToken(address token) external {
        require(token != address(0), "Zero token");
        registeredTokens[token] = true;
    }

    function setOperator(address op, bool active) external {
        operators[op] = active;
    }

    function createProposal(address token, string memory description)
        external
        onlyOperator(token)
    {
        Proposal storage p = _proposals[token].push();
        p.description = description;
        emit ProposalCreated(token, _proposals[token].length - 1, description);
    }

    function voteFor(address token, address voter, uint256 id, bool support)
        external
        onlyOperator(token)
    {
        Proposal storage p = _proposals[token][id];
        require(!p.finalized, "Finalized");
        require(!p.hasVoted[voter], "Voted");

        // You'd need a way to get token balance here securely
        // Assume caller verifies voting power off-chain or through a trusted hook
        uint256 weight = IERC20(token).balanceOf(voter);
        require(weight > 0, "No power");

        if (support) p.yesVotes += weight;
        else p.noVotes += weight;

        p.hasVoted[voter] = true;
        emit Voted(token, id, voter, support, weight);
    }

    function finalizeProposal(address token, uint256 id)
        external
        onlyOperator(token)
    {
        Proposal storage p = _proposals[token][id];
        require(!p.finalized, "Finalized");
        p.finalized = true;
        emit ProposalFinalized(token, id, p.yesVotes > p.noVotes);
    }

    function getProposal(address token, uint256 id)
        external
        view
        returns (string memory, uint256, uint256, bool)
    {
        Proposal storage p = _proposals[token][id];
        return (p.description, p.yesVotes, p.noVotes, p.finalized);
    }

    function proposalsLength(address token) external view returns (uint256) {
        return _proposals[token].length;
    }

    event ProposalCreated(address token, uint256 id, string description);
    event Voted(address token, uint256 id, address voter, bool support, uint256 weight);
    event ProposalFinalized(address token, uint256 id, bool passed);
}
