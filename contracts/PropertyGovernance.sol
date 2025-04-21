// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev All governance – proposal storage, events, and functions.
abstract contract PropertyTokenGovernance is ERC20 {
    struct Proposal {
        string description;
        uint256 yesVotes;
        uint256 noVotes;
        bool finalized;
        mapping(address => bool) hasVoted;
    }

    Proposal[] private _proposals;

    event ProposalCreated(uint256 indexed proposalId, string description);
    event Voted(
        uint256 indexed proposalId,
        address voter,
        bool support,
        uint256 weight
    );
    event ProposalFinalized(uint256 indexed proposalId, bool passed);

    /// @notice Create a new proposal.  Must be overridden with your onlyOperator guard.
    function createProposal(string memory description) public virtual {
        Proposal storage p = _proposals.push();
        p.description = description;
        emit ProposalCreated(_proposals.length - 1, description);
    }

    /// @notice Record a vote on behalf of `voter`.  Must be overridden with onlyOperator.
    function voteFor(
        address voter,
        uint256 proposalId,
        bool support
    ) public virtual {
        Proposal storage p = _proposals[proposalId];
        require(!p.finalized, "Proposal finalized");
        require(!p.hasVoted[voter], "Already voted");
        uint256 weight = balanceOf(voter);
        require(weight > 0, "No voting power");

        if (support) {
            p.yesVotes += weight;
        } else {
            p.noVotes += weight;
        }
        p.hasVoted[voter] = true;
        emit Voted(proposalId, voter, support, weight);
    }

    /// @notice Finalize a proposal.  Must be overridden with onlyOperator.
    function finalizeProposal(uint256 proposalId) public virtual {
        Proposal storage p = _proposals[proposalId];
        require(!p.finalized, "Already finalized");
        p.finalized = true;
        bool passed = p.yesVotes > p.noVotes;
        emit ProposalFinalized(proposalId, passed);
    }

    /// @notice Read out a proposal’s details.
    function getProposal(uint256 proposalId)
        public
        view
        virtual
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

    /// @notice How many proposals exist so far.
    function proposalsLength() public view virtual returns (uint256) {
        return _proposals.length;
    }
}
