pragma solidity ^0.4.25;

contract EmmSharedNodes {

    uint public constant MASTERNODE_DEPOSIT = 20000 * 10 ** 18;
    uint public constant MASTERNODE_WITHDRAW = 1999999 * 10 ** 16;
    uint public constant NODE_STOP_WITHDRAW_COMMISSION = 1 * 10 ** 16;
    uint public constant MAX_COMMISSION_PERCENT = 50;
    uint public constant ONE_ETZ = 10 ** 18;

    address public nodesContract;
    address public owner;
    address public processor;
    uint public ownerRewards = 0;
    uint8 public commissionPercent = 30;
    // Coins of contract owned and distributed by users and owner;
    uint public ownedCoins = 0;
    // Coins locked on masternodes
    uint public usedCoins = 0;

    // Managed nodes
    EmmSharedNodeProxy[] public nodes;
    uint public nextInactiveNode = 0;

    // User balances
    address[] public accounts;
    mapping (address => uint) public balances;

    event userDeposit(address addr, uint volume, uint totalVolume);
    event userWithdraw(address addr, uint volume, uint totalVolume);
    event nodeCreated(bytes32 id1, bytes32 id2);
    event nodeRemoved();

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier onlyProcessor() {
        require(msg.sender == owner || msg.sender == processor);
        _;
    }

    constructor(address _nodesContract) public {
        nodesContract = _nodesContract;
        owner = msg.sender;
        processor = msg.sender;
    }

    function changeOwner(address _newOwner) public onlyOwner {
        owner = _newOwner;
    }

    function changeProcessor(address _newProcessor) public onlyOwner {
        processor = _newProcessor;
    }

    function ownerWithdraw(uint _volume) public onlyOwner {
        uint volume;
        if (_volume > 0) {
            volume = _volume;
        } else {
            volume = ownerRewards;
        }
        require(ownerRewards >= volume);
        require(ownedCoins > volume);

        ownerRewards -= volume;

        releaseCoins(volume);

        msg.sender.transfer(volume);
        ownedCoins -= volume;

        emit userWithdraw(msg.sender, volume, balances[msg.sender]);
    }

    // Coin management

    function() payable public {
        if (msg.value >= ONE_ETZ) {
            deposit();
        } else if (msg.value == 0) {
            withdraw(0);
        } else {
            revert();
        }
    }

    function addReward() payable public {
    }

    function returnCoins() payable public {
    }

    function accountsCount() public view returns (uint count) {
        count = accounts.length;
    }

    function deposit() payable public {
        require(msg.value >= ONE_ETZ);

        uint len = accounts.length;
        bool exists = false;
        for (uint i = 0; i < len; i ++) {
            if (accounts[i] == msg.sender) {
                exists = true;
            }
        }
        if (!exists) {
            accounts.push(msg.sender);
        }

        uint newBalance = balances[msg.sender] + msg.value;
        balances[msg.sender] = newBalance;

        ownedCoins += msg.value;

        emit userDeposit(msg.sender, msg.value, newBalance);
    }

    function myBalance() constant public returns (uint balance) {
        balance = balances[msg.sender];
    }

    function getBalance(address _address) constant public returns (uint balance) {
        balance = balances[_address];
    }

    function withdraw(uint _volume) public {
        uint volume;
        if (_volume > 0) {
            volume = _volume;
            require(balances[msg.sender] >= volume);
        } else {
            volume = balances[msg.sender];
        }
        require(ownedCoins > volume);
        balances[msg.sender] -= volume;

        uint stoppedNodes = releaseCoins(volume);

        msg.sender.transfer(volume - stoppedNodes * NODE_STOP_WITHDRAW_COMMISSION);
        ownedCoins -= volume;

        emit userWithdraw(msg.sender, volume, balances[msg.sender]);
    }

    function releaseCoins(uint volume) private returns (uint nodesToStop){
        nodesToStop = 0;
        if (address(this).balance < volume) {
            uint left = volume - address(this).balance;
            nodesToStop = left / MASTERNODE_WITHDRAW;
            if (left % MASTERNODE_WITHDRAW != 0) {
                nodesToStop += 1;
            }

            for (uint i = 0; i < nodesToStop; i++) {
                stopTopNode();
            }
        }
        assert(address(this).balance >= volume);
    }

    // Node management

    function nodesCount() public view returns (uint count){
        count = nodes.length;
    }

    function createNewNode(bytes32 id1, bytes32 id2) public onlyProcessor {
        require(address(this).balance >= MASTERNODE_DEPOSIT);

        // Firstly, checking - do we have created inactive contract;
        EmmSharedNodeProxy proxy;
        if (nextInactiveNode < nodes.length) {
            proxy = nodes[nextInactiveNode];
        } else {
            // Creating new contract
            proxy = new EmmSharedNodeProxy(nodesContract);
            nodes.push(proxy);
        }
        nextInactiveNode++;

        usedCoins += MASTERNODE_DEPOSIT;
        proxy.register.value(MASTERNODE_DEPOSIT)(id1, id2);
    }

    function stopTopNode() private {
        require(nextInactiveNode > 0);
        EmmSharedNodeProxy proxy = nodes[nextInactiveNode - 1];
        nextInactiveNode--;
        usedCoins -= MASTERNODE_DEPOSIT;
        proxy.unregister();
    }

    // Reward distribution

    function changeCommission(uint8 _commission) public onlyOwner {
        require(_commission > 0);
        require(_commission <= MAX_COMMISSION_PERCENT);
        commissionPercent = _commission;
    }

    function undistributedRewards() public view returns (uint value) {
        value = address(this).balance - (ownedCoins - usedCoins);
    }

    function distributeRewards() public returns (uint distributed, uint toOwner){
        uint toDistribute = undistributedRewards();
        require(toDistribute > 0);
        require(address(this).balance >= toDistribute);

        uint toAccounts = toDistribute * (100 - commissionPercent) / 100;

        uint len = accounts.length;
        distributed = 0;
        for (uint i = 0; i < len; i++) {
            uint reward = toAccounts * balances[accounts[i]] / ownedCoins;
            distributed += reward;
            balances[accounts[i]] += reward;
        }

        toOwner = toDistribute - distributed;
        assert(toOwner > 0);
        ownerRewards += toOwner;
        ownedCoins += distributed + toOwner;
    }

    function takeAllUndistributed() public onlyOwner returns (uint _distributed){
        uint toDistribute = undistributedRewards();
        require(address(this).balance >= toDistribute);

        ownerRewards += toDistribute;
        ownedCoins += toDistribute;

        _distributed = toDistribute;
    }

}

// Contract to interact with Etz Masternodes Smart - register / unregister masternodes in network
contract EmmSharedNodeProxy {

    uint public constant MASTERNODE_DEPOSIT = 20000 * 10 ** 18;
    uint public constant MASTERNODE_WITHDRAW = 1999999 * 10 ** 16;

    address nodesContract;
    address public owner;
    bool public active = false;

    constructor(address _nodeContract) public {
        nodesContract = _nodeContract;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function () payable public {
        // For withdraw coins from Masternode Contract
    }

    function register(bytes32 id1, bytes32 id2) payable public onlyOwner {
        require(msg.value == MASTERNODE_DEPOSIT);
        require(address(this).balance == MASTERNODE_DEPOSIT);
        require(nodesContract.call.value(msg.value)(bytes4(keccak256("register(bytes32,bytes32)")), id1, id2));
        assert(address(this).balance == 0);
        active = true;
    }

    function unregister() public onlyOwner {
        require(address(this).balance == 0);
        require(nodesContract.call.value(0)());
        assert(address(this).balance == MASTERNODE_WITHDRAW);
        require(owner.call.value(address(this).balance)(bytes4(keccak256("returnCoins()"))));
        assert(address(this).balance == 0);
        active = false;
    }

}
