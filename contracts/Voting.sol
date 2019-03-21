pragma solidity 0.5.0;

// Intended use: lock withdrawal for a set time period
contract ProposalETZ {
    //Masternode
    struct Voter{
        uint    voteType;          //1 vote agree、2 not agree。
        uint    proposalIndex;
        uint    votedIndex;
        bool    isdelegate;
        address addr;
    }
    struct Delegate{
        address addr;
        bool    isdelegated;
    }
    //Proposal
    struct proposal {
        string  name;             //proposal name
        string  link;             //proposal link
        uint    applyAmount;      //proposal applyAmount
        uint    voteNumYes;
        uint    voteNumNo;
        uint    voteNumAct;
        bool    adopted;          //true--adopted。
        bool    passed;
        address addr;
        bool    sended;
        uint    blockStart;
    }
    struct proposalPay{
        address  addr;
        uint     eachAmount;
        bool     passed;
        bool     sended;
        uint     pIndex;
    }
    //budget
    struct Budget {
        uint  budgetForPay;
        uint  proposalPayed;
    }

    uint public constant etzPerProposal= 10 * 10 ** 18; //payed for each proposal actully 10ETZ
    uint public constant votePeriod       =  1200000; //3600 for test actully 1200000 blocks
    uint public budgetAddedChain = votePeriod * 1125/10000 * 10 ** 18;
    address public owner;
    address public MasterAddr;//Masternode contract Addr
    uint public blockStart = block.number;
    uint public blockOrigin = block.number;
    uint public VoteIndex =1;
    mapping(address => Voter) public voters;
    mapping(address => Delegate) public delegateVoters;
    mapping(address => proposalPay) public proposalsAddr;
    mapping(uint => uint) public mapIndex;

    proposal[] public proposals;
    uint []    public sortedProposals;
    Budget     budget = Budget(budgetAddedChain,0);
    bool       public status = false;

    //  event Submit(string indexed name,string indexed link,string uint applyAmount,uint indexed voteNumYes,
    //  uint indexed voteNumNo,bool indexed adopted,bool indexed passed,address indexed addr);
    event submit_event(string pname, string plink, uint papplyAmount,address paddr,uint VoteIndex);
    event vote_event(uint pIndex,uint voteNumYes, uint voteNumNo,uint voteNumAct, bool adopted);

    constructor(address _MasterAddr) public {
        MasterAddr = _MasterAddr;
    }

    function () payable external {
        proposalPay storage pl = proposalsAddr[msg.sender];
        //get back payed coins
        if (msg.value == 0){
            require (block.number > blockOrigin + votePeriod);
            require (pl.passed == true);
            require (pl.sended == false);
            require((pl.eachAmount<= 1000000* 10 ** 18)&&(pl.eachAmount>=0));
            uint pIndex = pl.pIndex;
            pl.sended   = true;
            proposals[pIndex].sended = true;
            msg.sender.transfer(pl.eachAmount);
        }

    }

    function proposalSubmit(string memory pname, string memory plink, uint papplyAmount, address paddr) payable public {
        require(msg.value == etzPerProposal,"send 10 etz for a proposal submit");
        require((papplyAmount<= 10000000* 10 ** 18)&&(papplyAmount>=0));
        proposals.push(proposal({
            name:pname,
            link:plink,
            applyAmount:papplyAmount,
            voteNumYes:0,
            voteNumNo:0,
            voteNumAct:0,
            adopted:false,
            passed:false,
            addr:paddr,
            sended:false,
            blockStart:blockStart
            }));
        budget.budgetForPay   = budget.budgetForPay +  etzPerProposal;
        emit submit_event(pname,plink,papplyAmount,paddr,VoteIndex);

    }
    function delegate(address addr) public{
        bytes8 ID;
        Voter storage sender = voters [msg.sender];
        Delegate storage dl = delegateVoters[addr];
        if(!sender.isdelegate)
        {
            ID = Masternode(MasterAddr).getId(msg.sender);//Masternode if the return not be zero。
            require(ID !=bytes8(0), "The voter is not a masternode");
            dl.isdelegated = true;
            dl.addr = msg.sender;
            sender.isdelegate = true;
            sender.addr = addr;
        }
        else
        {
            dl.isdelegated = false;
            sender.isdelegate = false;
        }
    }

    //Masternode vote
    function vote(uint index, uint  voteType) public {
        bytes8 ID;
        Voter storage sender = voters [msg.sender];
        Delegate storage dl = delegateVoters[msg.sender];
        uint voterNum =  masterNodeNum() ;
        uint pIndex = index;
        uint voterStartBlock;
        address masterAddr;
        bool sortedIn = false;

        masterAddr = msg.sender;
        if((dl.isdelegated == true)||(sender.isdelegate == true))
        {
            masterAddr = dl.addr;


        }
        ID = Masternode(MasterAddr).getId(masterAddr);//Masternode if the return not be zero。
        (, , , ,voterStartBlock , , ,) = Masternode(MasterAddr).getInfo(ID);

        require(ID !=bytes8(0), "The voter is not a masternode");
        require(sender.votedIndex < VoteIndex, "The voter has already voted");
        require((block.number-proposals[pIndex].blockStart)<votePeriod, "The voter can only vote the proposal in the current period ");
        require((block.number-voterStartBlock)>votePeriod,"The masternode must on line for a vote period ");
        if(voteType == 1)
        {
            proposals[pIndex].voteNumYes += 1;
        }
        else if(voteType == 2)
        {
            proposals[pIndex].voteNumNo  += 1;
        }
        // judge the proposals for adopted
        if(proposals[pIndex].voteNumYes > proposals[pIndex].voteNumNo)
        {
            proposals[pIndex].voteNumAct = proposals[pIndex].voteNumYes - proposals[pIndex].voteNumNo;
        }
        else
        {
            proposals[pIndex].voteNumAct = 0;
        }
        //adopted if the voteNumYes - voteNumNo > voterNum/10
        if(proposals[pIndex].voteNumAct > (voterNum/10))
        {
            proposals[pIndex].adopted = true;
            for(uint i=0;i<sortedProposals.length;i++)
            {
                if(sortedProposals[i]==pIndex)
                {
                    sortedIn = true;
                    break;
                }
            }
            if(!sortedIn)
            {
                sortedProposals.push(pIndex);
            }
        }
        else
        {
            proposals[pIndex].adopted = false;
        }
        sender.votedIndex = VoteIndex ;
        sender.proposalIndex = pIndex;

        if((dl.isdelegated == true)||(sender.isdelegate == true))
        {
            Voter storage sender1 = voters [dl.addr];
            sender1.votedIndex = VoteIndex ;
            sender1.proposalIndex = pIndex;
        }

        emit vote_event(pIndex,proposals[pIndex].voteNumYes,proposals[pIndex].voteNumNo,proposals[pIndex].voteNumAct,proposals[pIndex].adopted);
        if(sortedProposals.length>0)
        {
            sortProposal();
            preSend();
        }
    }

    function sortProposal()  private{
        //sort proposals sortedProposals.length<=10
        uint proposalTmp;
        uint index1;
        uint index2;
        for(uint i=0;i<sortedProposals.length-1;i++) //
        {
            for(uint j=0;j<sortedProposals.length-1-i;j++)
            {
                index1 = sortedProposals[j];
                index2 = sortedProposals[j+1];
                if(proposals[index1].voteNumAct<proposals[index2].voteNumAct)
                {
                    proposalTmp          = sortedProposals[j+1];
                    sortedProposals[j+1] = sortedProposals[j];
                    sortedProposals[j]   = proposalTmp;
                }
            }
        }
    }

    //calcute the appplyAmount
    function preSend()  private{
        uint pIndex;
        uint payedSum = 0;
        address addr;

        for(uint i =0;i<sortedProposals.length;i++)
        {
            pIndex = sortedProposals[i];
            payedSum  += proposals[pIndex].applyAmount;
            if((payedSum < budget.budgetForPay)&&(proposals[pIndex].adopted))
            {
                proposals[pIndex].passed = true;
                addr = proposals[pIndex].addr;
                proposalPay storage pl = proposalsAddr[addr];
                pl.addr = proposals[pIndex].addr;
                pl.eachAmount = proposals[pIndex].applyAmount;
                pl.passed = proposals[pIndex].passed;
                pl.sended = false;
                pl.pIndex    =pIndex;
            }
            else
            {
                payedSum  -= proposals[pIndex].applyAmount;
                proposals[pIndex].passed = false;
            }
        }
        //buget for the next vote
        budget.proposalPayed =  payedSum;
    }

    //start a new round of voting
    function startRefresh() public{
        //Refresh parameter
        require(block.number - blockStart > votePeriod);
        delete sortedProposals;
        blockStart += votePeriod;
        VoteIndex  += 1;
        status = true;
        budget.budgetForPay  = budget.budgetForPay + budgetAddedChain - budget.proposalPayed;
    }

    function getContractBalance() public view returns (uint) {
        return address(this).balance;
    }
    function getbudget() public view returns (uint) {
        return budget.budgetForPay;
    }
    function getPayed() public view returns (uint) {
        return budget.proposalPayed;
    }
    function getMasterId(address addr) public view returns (bytes8) {
        return Masternode(MasterAddr).getId(addr);
    }

    //calcute the masternode number
    function masterNodeNum() public view returns (uint) {
        uint voterNum;
        voterNum = Masternode(MasterAddr).count();
        return voterNum;
    }

    function getProposalsNum() public view returns (uint) {

        return proposals.length;
    }
    function getIndex(uint pIndex)public view returns(uint)
    {
        return mapIndex[pIndex];
    }

}

contract Masternode {
    uint public count;
    struct node {
        bytes32 id1;
        bytes32 id2;
        bytes8 preId;
        bytes8 nextId;
        address account;
        uint block;
        uint blockOnlineAcc;
        uint blockLastPing;
    }
    mapping (bytes8 => node) nodes;
    function getId(address ) pure public returns (bytes8 ){}
    function getInfo(bytes8 ) pure public returns (
        bytes32 ,
        bytes32 ,
        bytes8 ,
        bytes8 ,
        uint ,
        address ,
        uint ,
        uint
    ){}
}