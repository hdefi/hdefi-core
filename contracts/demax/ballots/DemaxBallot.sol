// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.6.6;

import '../interfaces/IERC20.sol';
import '../interfaces/IDemaxGovernance.sol';

/**
 * @title DemaxBallot
 * @dev Implements voting process along with vote delegation
 */
contract DemaxBallot {

    struct Voter {
        uint weight; // weight is accumulated by delegation
        bool voted;  // if true, that person already voted
        uint vote;   // index of the voted proposal
    }

    mapping(address => Voter) public voters;
    mapping(uint => uint) public proposals;

    address public governor;
    address public proposer;
    uint public value;
    uint public endBlockNumber;
    bool public ended;
    string public subject;
    string public content;

    uint private constant NONE = 0;
    uint private constant YES = 1;
    uint private constant NO = 2;

    uint public total;
    uint public createTime;
    address public factory;

    modifier onlyGovernor() {
        require(msg.sender == governor, 'DemaxBallot: FORBIDDEN');
        _;
    }

    /**
     * @dev Create a new ballot.
     */
    constructor() public {
        factory = msg.sender;
        proposals[YES] = 0;
        proposals[NO] = 0;
        createTime = block.timestamp;
    }

    function initialize(address _proposer, uint _value, uint _endBlockNumber, address _governor, string memory _subject, string memory _content) public {
        require(msg.sender == factory, 'DemaxBallot: FORBIDDEN');
        proposer = _proposer;
        value = _value;
        endBlockNumber = _endBlockNumber;
        governor = _governor;
        subject = _subject;
        content = _content;
    }

    /**
     * @dev Give 'voter' the right to vote on this ballot.
     * @param voter address of voter
     */
    function _giveRightToVote(address voter) private returns (Voter storage) {
        require(block.number < endBlockNumber, "Ballot is ended");
        Voter storage sender = voters[voter];
        require(!sender.voted, "You already voted");
        sender.weight += IERC20(governor).balanceOf(voter);
        require(sender.weight != 0, "Has no right to vote");
        return sender;
    }

    /**
     * @dev Give your vote (including votes delegated to you) to proposal 'proposals[proposal].name'.
     * @param proposal index of proposal in the proposals array
     */
    function vote(uint proposal) public {
        Voter storage sender = _giveRightToVote(msg.sender);
        require(proposal==YES || proposal==NO, 'Only vote 1 or 2');
        sender.voted = true;
        sender.vote = proposal;
        proposals[proposal] += sender.weight;
        total += sender.weight;
        IDemaxGovernance(governor).resetStaking(msg.sender);
    }

    /**
     * @dev Computes the winning proposal taking all previous votes into account.
     * @return winningProposal_ index of winning proposal in the proposals array
     */
    function winningProposal() public view returns (uint) {
        if (proposals[YES] > proposals[NO]) {
            return YES;
        } else if (proposals[YES] < proposals[NO]) {
            return NO;
        } else {
            return NONE;
        }
    }

    function result() public view returns (bool) {
        uint winner = winningProposal();
        if (winner == YES) {
            return true;
        }
        return false;
    }

    function end() public onlyGovernor returns (bool) {
        require(block.number >= endBlockNumber, "ballot not yet ended");
        require(!ended, "end has already been called");
        ended = true;
        return result();
    }

    function weight(address user) external view returns (uint) {
        Voter memory voter = voters[user];
        return voter.weight;
    }

}
