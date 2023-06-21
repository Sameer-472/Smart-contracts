// SPDX-License-Identifier: MIT
pragma solidity  ^0.8.18;

contract Voting {

    uint256 public maxCandidates = 2;
    uint256 public noOfCandidates = 0;
    bool votingStart = false;
    address private owner;
    uint256 public winnerId = 0;


    constructor() {
        owner = msg.sender;
    }
    
    struct Voter{
        address candidateAddr;
        address voterAddr;
    }

    struct Candidate{
        string name;
        uint256 age;
        uint256 noOfVotes;
    }

    // event VotingStarted(bool _bool);
    event candidateAdded(string indexed  name , uint256 age);
    event voteSubmited(uint256 candidateId);
    mapping (uint256 => Candidate) public candidates;

    mapping (address => bool) public voter;

    modifier VotingStarted{
        require(votingStart == true  , "Voting is not started yet or closed");
        _;
    }

    modifier onlyOwner(){
        require(owner == msg.sender , "your are not authorized");
        _;
    }

    modifier checkCandidateAge(uint256 _age){
        require(_age >= 18 , "candidate age should be 18 or above");
        _;
    }

    modifier checkLimit{
        require(noOfCandidates < maxCandidates , "Execeed no of candidate");
        _;
    }

    modifier checkVoter(address _addr){
        require(voter[_addr] == false , "You Already cast a vote");
        _;
    }

    function addCandidate(string memory _name , uint256 _age) public checkCandidateAge(_age) checkLimit onlyOwner{
        noOfCandidates += 1;
        candidates[noOfCandidates] = Candidate(_name , _age , 0);
        emit candidateAdded(_name, _age);
    }

    function startVoting()public onlyOwner{
        votingStart = true;
    }

    function submitVote(uint256 _candidateId) public payable  VotingStarted checkVoter(msg.sender) {
        voter[msg.sender] = true;
        candidates[_candidateId].noOfVotes +=1;
        emit voteSubmited(_candidateId);
    }

    function EndVoting() public onlyOwner returns(uint256){
        uint256 voteCounter = 0;
        uint256 winner = 0;
        for (uint i = 1; i<=noOfCandidates;) 
        {
            if(candidates[i].noOfVotes > voteCounter){
                voteCounter = candidates[i].noOfVotes;
                winner = i;
            }
            else if(candidates[i].noOfVotes == voteCounter){
                winner = 0;
            }
            unchecked {
                ++i;
            }
        }
        winnerId = winner;
        votingStart = false;
        return  winner;
    }
}