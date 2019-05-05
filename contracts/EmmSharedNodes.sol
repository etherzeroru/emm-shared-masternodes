pragma solidity 0.5.0;

contract EmmSharedNodes {

    uint public constant MASTERNODE_DEPOSIT = 20000 * 10 ** 18;
    uint public constant MASTERNODE_WITHDRAW = 1999999 * 10 ** 16;
    uint public constant NODE_STOP_WITHDRAW_COMMISSION = 1 * 10 ** 16;
    uint public constant MAX_COMMISSION_PERCENT = 50;
    uint public constant ONE_ETZ = 10 ** 18;

    address payable public nodesContract;
    address public votingContract;
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

    // ================ Safe Math ================

    // Safe Math: addition
    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);

        return c;
    }

    // Safe Math: subtraction
    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;

        return c;
    }

    // Safe Math: Multiplication
    function safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b);

        return c;
    }

    // Safe Math: Division
    function safeDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0);
        uint256 c = a / b;

        return c;
    }

    // Safe Math: Modular
    function safeMod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }

    // ================ Main contract ================

    // Only for owner
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    // Only for processor or owner
    modifier onlyProcessorOrOwner() {
        require(msg.sender == processor || msg.sender == owner);
        _;
    }

    // Creating Shared Nodes Managing contract with Masternode Managing contract address (0x000000000000000000000000000000000000000a)
    // and voting contract address (0x4761977f757e3031350612d55bb891c8144a414b)
    constructor(address payable _nodesContract, address _votingContract) public {
        nodesContract = _nodesContract;
        votingContract = _votingContract;
        owner = msg.sender;
        processor = msg.sender;
    }

    // Change contract owner
    function changeOwner(address _newOwner) public onlyOwner {
        owner = _newOwner;
    }

    // Change contract processor
    function changeProcessor(address _newProcessor) public onlyOwner {
        processor = _newProcessor;
    }

    // Withdraw owner rewards (commission).
    function ownerWithdraw(uint _volume) public onlyOwner {
        uint volume;
        if (_volume > 0) {
            volume = _volume;
        } else {
            volume = ownerRewards;
        }
        require(ownerRewards >= volume);
        require(ownedCoins >= volume);

        ownerRewards = safeSub(ownerRewards, volume);

        releaseCoins(volume);

        ownedCoins = safeSub(ownedCoins, volume);
        msg.sender.transfer(volume);

        emit userWithdraw(msg.sender, volume, balances[msg.sender]);
    }

    // ================ Coin Management ================

    // Invest or withdraw coins by users. Proxy method to deposit() or withdraw() for easily interacting with contract
    function() payable external {
        if (msg.value >= ONE_ETZ) {
            deposit();
        } else if (msg.value == 0) {
            withdraw(0);
        } else {
            revert();
        }
    }

    // Special util method to test reward charging from Masternode Managing contract
    function addReward() payable external {
    }

    // Method to return coins from proxy contract. Usually calling by proxy contract
    function returnCoins() payable external {
    }

    // Returns count of users ever used the contract
    function accountsCount() public view returns (uint count) {
        count = accounts.length;
    }

    // Main investing method. Payable volume will be invested to Shared Nodes system
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

        uint newBalance = safeAdd(balances[msg.sender], msg.value);
        balances[msg.sender] = newBalance;

        ownedCoins = safeAdd(ownedCoins, msg.value);

        emit userDeposit(msg.sender, msg.value, newBalance);
    }

    // Check balances of caller
    function myBalance() view external returns (uint balance) {
        balance = balances[msg.sender];
    }

    // Check balance of user
    function getBalance(address _address) view public returns (uint balance) {
        balance = balances[_address];
    }

    // Main withdraw method. It stops top nodes if contract balance is not enough for requested withdraw volume.
    function withdraw(uint _volume) public {
        uint volume;
        if (_volume > 0) {
            volume = _volume;
            require(balances[msg.sender] >= volume);
        } else {
            volume = balances[msg.sender];
        }

        require(ownedCoins >= volume);
        balances[msg.sender] = safeSub(balances[msg.sender], volume);
        uint stoppedNodes = releaseCoins(volume);
        uint stopCommission = safeMul(stoppedNodes, NODE_STOP_WITHDRAW_COMMISSION);

        ownedCoins = safeSub(ownedCoins, volume);
        msg.sender.transfer(safeSub(volume, stopCommission));

        emit userWithdraw(msg.sender, volume, balances[msg.sender]);
    }

    // Returns coins from Masternode Managing contract via Shared Nodes Proxy contract to Shared Nodes Managing contract
    function releaseCoins(uint volume) private returns (uint nodesToStop){
        nodesToStop = 0;
        if (address(this).balance < volume) {
            uint left = safeSub(volume, address(this).balance);
            nodesToStop = safeDiv(left, MASTERNODE_WITHDRAW);
            if (safeMod(left, MASTERNODE_WITHDRAW) != 0) {
                nodesToStop = safeAdd(nodesToStop, 1);
            }

            for (uint i = 0; i < nodesToStop; i++) {
                stopTopNode();
            }
        }
        assert(address(this).balance >= volume);
    }

    // ================ Node management ================

    // Returns count of ever created nodes
    function nodesCount() public view returns (uint count){
        count = nodes.length;
    }

    // Creates new node with masternode data (id1, id2) via new proxy contract or used before stopped proxy contract
    // and sends MASTERNODE_DEPOSIT Etz via this contract to Masternodes Managing contract
    function createNewNode(bytes32 id1, bytes32 id2) public onlyProcessorOrOwner {
        require(address(this).balance >= MASTERNODE_DEPOSIT);

        // Firstly, checking - do we have created inactive contract;
        EmmSharedNodeProxy proxy;
        if (nextInactiveNode < nodes.length) {
            proxy = nodes[nextInactiveNode];
        } else {
            // Creating new contract
            proxy = new EmmSharedNodeProxy(nodesContract, votingContract);
            nodes.push(proxy);
        }
        nextInactiveNode = safeAdd(nextInactiveNode, 1);

        usedCoins = safeAdd(usedCoins, MASTERNODE_DEPOSIT);
        proxy.register.value(MASTERNODE_DEPOSIT)(id1, id2);
    }

    // Stops one top node and returns MASTERNODE_DEPOSIT - NODE_STOP_WITHDRAW_COMMISSION to Shared Nodes Managing contract via proxy contract
    function stopTopNode() private {
        require(nextInactiveNode > 0);
        nextInactiveNode = safeSub(nextInactiveNode, 1);
        EmmSharedNodeProxy proxy = nodes[nextInactiveNode];
        usedCoins = safeSub(usedCoins, MASTERNODE_DEPOSIT);
        proxy.unregister();
    }

    // ============== Reward distribution ==============

    // Change commission of owner
    function changeCommission(uint8 _commission) external onlyOwner {
        require(_commission > 0);
        require(_commission <= MAX_COMMISSION_PERCENT);
        commissionPercent = _commission;
    }

    // Get undistributed rewards
    function undistributedRewards() public view returns (uint value) {
        uint left = safeSub(ownedCoins, usedCoins);
        value = safeSub(address(this).balance, left);
    }

    // Distribute rewards between owner (commission percent part) and users according their parts
    function distributeRewards() public returns (uint distributed, uint toOwner){
        uint toDistribute = undistributedRewards();
        require(toDistribute > 0);
        require(address(this).balance >= toDistribute);

        uint toAccounts = safeDiv(safeMul(toDistribute, safeSub(100, commissionPercent)), 100);

        uint len = accounts.length;
        distributed = 0;
        for (uint i = 0; i < len; i++) {
            uint reward = safeDiv(safeMul(toAccounts,  balances[accounts[i]]), ownedCoins);
            distributed = safeAdd(distributed, reward);
            balances[accounts[i]] = safeAdd(balances[accounts[i]], reward);
        }

        toOwner = safeSub(toDistribute, distributed);
        assert(toOwner > 0);
        ownerRewards = safeAdd(ownerRewards, toOwner);
        ownedCoins = safeAdd(ownedCoins, safeAdd(distributed, toOwner));
    }

    // Take all undistributed rewards to owner. Usually not used. Created as fallback to take all money to owner and send to users after that with wallet.
    function takeAllUndistributed() external onlyOwner returns (uint _distributed) {
        uint toDistribute = undistributedRewards();
        require(address(this).balance >= toDistribute);

        ownerRewards = safeAdd(ownerRewards, toDistribute);
        ownedCoins = safeAdd(ownedCoins, toDistribute);

        _distributed = toDistribute;
    }

    // Vote for proposal (only for owner)
    function vote(uint index, uint  voteType) external onlyOwner  {
        for (uint i = 0; i < nextInactiveNode; i++) {
            EmmSharedNodeProxy proxy = nodes[i];
            proxy.vote(index, voteType);
        }
    }

}

// Contract to interact with Etz Masternodes Smart - register / unregister masternodes in network
contract EmmSharedNodeProxy {

    uint public constant MASTERNODE_DEPOSIT = 20000 * 10 ** 18;
    uint public constant MASTERNODE_WITHDRAW = 1999999 * 10 ** 16;

    address payable public nodesContract;
    address public votingContract;
    address public owner;
    bool public active = false;

    // Creating Shared Nodes Proxy contract with Masternode Managing contract address (0x000000000000000000000000000000000000000a)
    // and voting contract address (0x4761977f757e3031350612d55bb891c8144a414b)
    constructor(address payable _nodeContract, address _votingContract) public {
        nodesContract = _nodeContract;
        votingContract = _votingContract;
        owner = msg.sender;
    }

    // Only for owner modifier
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function () payable external {
        // For withdraw coins from Masternode Contract
    }

    // Register masternode with masternode data (id1, id2) and send MASTERNODE_DEPOSIT to Masternode Managing Contract
    function register(bytes32 id1, bytes32 id2) payable external onlyOwner {
        require(msg.value == MASTERNODE_DEPOSIT);
        require(address(this).balance == MASTERNODE_DEPOSIT);
        (bool success,) = nodesContract.call.value(msg.value)(abi.encodeWithSignature("register(bytes32,bytes32)", id1, id2));
        require(success);
        assert(address(this).balance == 0);
        active = true;
    }

    // Unregister masternode and send MASTERNODE_DEPOSIT from Masternode Managing Contract to Shared Nodes Managing Contract
    function unregister() public onlyOwner {
        require(address(this).balance == 0);
        //nodesContract.transfer(0);
        (bool successWithdraw,) = nodesContract.call(abi.encodeWithSignature("()"));
        require(successWithdraw);

        assert(address(this).balance == MASTERNODE_WITHDRAW);
        (bool successReturn,) = owner.call.value(address(this).balance)(abi.encodeWithSignature("returnCoins()"));
        require(successReturn);
        assert(address(this).balance == 0);
        active = false;
    }

    // Vote for proposal (only for owner)
    function vote(uint index, uint  voteType) public onlyOwner {
        (bool success,) = votingContract.call(abi.encodeWithSignature("vote(uint, uint)", index, voteType));
        // require(success); <- illegal voters should be skipped
    }

}
