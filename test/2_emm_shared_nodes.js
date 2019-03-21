let Masternode = artifacts.require("./Masternode.sol");
let Voting = artifacts.require("./ProposalETZ.sol");
let EmmSharedNodes = artifacts.require("./EmmSharedNodes.sol");
let EmmSharedNodeProxy = artifacts.require("./EmmSharedNodeProxy.sol");

let masternode;
let voting;
let emmSharedNodes;

function toEther(number) {
    return parseFloat(web3.utils.fromWei(BigInt(number).toString(10)).toString());
}

async function balance(account) {
    return toEther(await web3.eth.getBalance(account));
}

async function printState() {
    console.log('---------------------');
    console.log('Contract balance: ', balance(emmSharedNodes.address));
    console.log('Owner rewards', toEther(await emmSharedNodes.ownerRewards()));
    console.log('Commission', (await emmSharedNodes.commissionPercent()).toString());
    console.log('Owned Coins', toEther(await emmSharedNodes.ownedCoins()));
    console.log('Used Coins', toEther(await emmSharedNodes.usedCoins()));

    let accountsLen = 0 + (await emmSharedNodes.accountsCount()).toString();
    console.log('Balances (', accountsLen, '):');
    for (let i = 0; i < accountsLen; i ++) {
        let address = await emmSharedNodes.accounts(i);
        let value = await emmSharedNodes.getBalance(address);
        console.log(address, ': ', toEther(value));
    }

    let nodesLen = 0 + (await emmSharedNodes.nodesCount()).toString();
    console.log('Nodes (', nodesLen ,'):');
    for (let i = 0; i < nodesLen; i ++) {
        let address = await emmSharedNodes.nodes(i);
        let active = await EmmSharedNodeProxy.at(address).active();
        let nodeId = await masternode.getId(address);
        console.log(address, ' - ', active ? 'active' : 'inactive', ' - ',  nodeId);
    }

}

contract('Emm Shared Nodes', async (accounts) => {

    it('Deploy EmmSharedNodes', async () => {
        masternode = await Masternode.new({from: accounts[9]});
        voting = await Voting.new(masternode.address, {from: accounts[9]});
        emmSharedNodes = await EmmSharedNodes.new(masternode.address, voting.address, {from: accounts[0]});
        assert.isNotNull(emmSharedNodes);
    });

    it('Check owner and processor', async () => {
        assert.equal(accounts[0], await emmSharedNodes.owner());
        assert.equal(accounts[0], await emmSharedNodes.processor());

        try {
            await emmSharedNodes.changeOwner(accounts[2], {from: accounts[1]});
            assert.fail("Allows to change owner from other account")
        } catch (e) {
        }
        assert.equal(accounts[0], await emmSharedNodes.owner());

        try {
            await emmSharedNodes.changeProcessor(accounts[2], {from: accounts[1]});
            assert.fail("Allows to change processor from other account")
        } catch (e) {
        }
        assert.equal(accounts[0], await emmSharedNodes.processor());

        await emmSharedNodes.changeOwner(accounts[2], {from: accounts[0]});
        assert.equal(accounts[2], await emmSharedNodes.owner(), 'Bad owner after changing');

        await emmSharedNodes.changeProcessor(accounts[3], {from: accounts[2]});
        assert.equal(accounts[3], await emmSharedNodes.processor(), 'Bad processor after changing');

        await emmSharedNodes.changeOwner(accounts[0], {from: accounts[2]});
        await emmSharedNodes.changeProcessor(accounts[0], {from: accounts[0]});
    });

    it('Send small money to shared nodes and check balance', async () => {
        try {
            const tx = await emmSharedNodes.deposit({
                to: emmSharedNodes.address,
                from: accounts[1],
                value: 100 * 10 ** 18,
                gasLimit: 270000
            });
            assert.isNotNull(tx);

            const bal = await emmSharedNodes.myBalance({from: accounts[1]});
            assert.equal(100, web3.utils.fromWei(bal), "Wrong balance on contract");

        } catch (e) {
            console.log(e);
            assert.fail(e);
        }
    });

    it('Withdraw money without node stopping', async () => {
        const accountVolumeBefore = await balance(accounts[1]);
        const userBalanceBefore = parseFloat(web3.utils.fromWei(await emmSharedNodes.myBalance({from: accounts[1]})).toString());
        const contractBalanceBefore = await balance(emmSharedNodes.address);

        await emmSharedNodes.withdraw(BigInt(10 * 10 ** 18).toString(10), {from: accounts[1]});

        const accountVolumeAfter = await balance(accounts[1]);
        const userBalanceAfter = parseFloat(web3.utils.fromWei(await emmSharedNodes.myBalance({from: accounts[1]})).toString());
        const contractBalanceAfter = await balance(emmSharedNodes.address);

        assert.equal(userBalanceBefore - 10, userBalanceAfter, "Shared Nodes user balance decreased");
        assert.equal(contractBalanceBefore - 10, contractBalanceAfter, "Shared Nodes contract balance decreased");
        assert.ok(accountVolumeAfter - accountVolumeBefore > 9.99, "ETZ account balance increased"); // Using 9.99 because of gas using. Impossible to set gas price = 0*/
    });

    it('Masternode creation', async () => {
        await emmSharedNodes.deposit({
            from: accounts[1],
            value: BigInt(20000 * 10 ** 18).toString(10),
            gasLimit: 27000
        });
        assert.ok(20000 <= parseFloat(web3.utils.fromWei(await emmSharedNodes.myBalance({from: accounts[1]}))).toString());
        assert.ok(20000 <= await balance(emmSharedNodes.address), "Balance of contract is not enough");

        await emmSharedNodes.createNewNode('0xd853c35eee71c04a0403586a70c05d4d7866a81a826795cc1c8dff8a32646c72', '0xb81c634b04473192aa746a011a34d96cac4651cfc16847f88cee1189fc765877');
        assert.isNotNull(await emmSharedNodes.nodes(0));

        let proxy = await EmmSharedNodeProxy.at(await emmSharedNodes.nodes(0));
        assert.ok(await proxy.active());

        const nodeId = await masternode.getId(proxy.address);
        assert.notEqual("0x0000000000000000", nodeId);

    });

    it('Add reward and distribute deposit', async () => {

        assert.isNotNull(await emmSharedNodes.nodes(0));
        let proxy = await EmmSharedNodeProxy.at(await emmSharedNodes.nodes(0));
        assert.ok(await proxy.active());

        emmSharedNodes.addReward({
           from: accounts[5],
           to: emmSharedNodes.address,
           value: BigInt(100 * 10 ** 18).toString(10),
           gasLimit: 270000
        });

        await emmSharedNodes.deposit({
           from: accounts[4],
           value: BigInt(14113 * 10 ** 18).toString(10),
           gasLimit: 27000
        });

        // await printState();

        emmSharedNodes.distributeRewards();

        const first = await emmSharedNodes.getBalance(await emmSharedNodes.accounts(0));
        const second = await emmSharedNodes.getBalance(await emmSharedNodes.accounts(1));
        const ownerRewards = await emmSharedNodes.ownerRewards();

        // 70 to accounts, 30 to owner
        assert.equal(70, toEther(first.add(second)) - 20090 - 14113);
        assert.equal(30, toEther(ownerRewards));

        // await printState();
    });

    it('Withdraw money with masternode destruction', async () => {
         assert.isNotNull(await emmSharedNodes.nodes(0));
         let proxy = await EmmSharedNodeProxy.at(await emmSharedNodes.nodes(0));
         assert.ok(await proxy.active());
         assert.ok(await balance(emmSharedNodes.address) < 20000, "Shared Nodes Contract balance too big");

         let oldUserBalance = await balance(accounts[1]);
         await emmSharedNodes.withdraw(BigInt(15000 * 10 ** 18).toString(10), {from: accounts[1], gasLimit: 30000000});
         assert.ok(!await proxy.active(), "Node should be inactive");
         assert.ok(Math.abs(oldUserBalance + 15000 - await balance(accounts[1])) < 0.09, "User balance wrong")
    });

    it('Old node recreate and new node create', async () => {
        assert.isNotNull(await emmSharedNodes.nodes(0));
        let proxy = await EmmSharedNodeProxy.at(await emmSharedNodes.nodes(0));
        assert.ok(!await proxy.active());

        await emmSharedNodes.deposit({
            from: accounts[1],
            value: BigInt(16000 * 10 ** 18).toString(10),
            gasLimit: 27000
        });

        await emmSharedNodes.deposit({
            from: accounts[2],
            value: BigInt(16000 * 10 ** 18).toString(10),
            gasLimit: 27000
        });

        await emmSharedNodes.createNewNode('0xd853c35eee71c04a0403586a70c05d4d7866a81a826795cc1c8dff8a32646c72', '0xb81c634b04473192aa746a011a34d96cac4651cfc16847f88cee1189fc765877');
        await emmSharedNodes.createNewNode('0xa3d6ac24b5372bd1d75b5dbc888f018273b8b5ec8b7e71b6441235c7f5598805', '0x1adb6ba378ed3319603a69f2a9d259eba86f0f881b8c43afb5f55643725d0200');

        let secondProxy = await EmmSharedNodeProxy.at(await emmSharedNodes.nodes(1));
        assert.ok(await proxy.active());
        assert.ok(await secondProxy.active());
    });

    it ('Try to withdraw over limit with stopping node', async () => {
        assert.isNotNull(await emmSharedNodes.nodes(0));
        assert.isNotNull(await emmSharedNodes.nodes(1));
        let proxy = await EmmSharedNodeProxy.at(await emmSharedNodes.nodes(0));
        let secondProxy = await EmmSharedNodeProxy.at(await emmSharedNodes.nodes(1));
        assert.ok(await proxy.active());
        assert.ok(await secondProxy.active());

        try {
            await emmSharedNodes.withdraw(BigInt(15000 * 10 ** 18).toString(10), {from: accounts[4], gasLimit: 270000});
            assert.fail()
        } catch (e) {
        }

        assert.ok(await proxy.active());
        assert.ok(await secondProxy.active());
    });

    it ('Setup proposal', async() => {

        let oldCount = (await voting.getProposalsNum()).toString();
        await voting.proposalSubmit("First one", "This is first proposal!", BigInt(1000000 * 10 ** 18).toString(10), accounts[7], {value: 10 * 10 ** 18});
        let newCount = (await voting.getProposalsNum()).toString();

        assert.ok( parseInt(newCount) === parseInt(oldCount) + 1, "Proposal count wrong");
    });

    it ('Try to vote (fail)', async() => {
        let proposal = await voting.proposals(0);
        let yesBefore = parseInt(proposal.voteNumYes.toString());
        let noBefore = parseInt(proposal.voteNumNo.toString());

        await emmSharedNodes.vote(0, 1);

        let proposalAfterFail = await voting.proposals(0);
        let yesAfterFail = parseInt(proposalAfterFail.voteNumYes.toString());
        let noAfterFail = parseInt(proposalAfterFail.voteNumNo.toString());

        assert.ok(yesBefore === yesAfterFail, "Yes shouldn't change");
        assert.ok(noBefore === noAfterFail, "No shouldn't change");
    });

    it ('Setup another proposal', async() => {

        for (let i = 1; i <= 220; i++) {
            if (i % 20 === 0) {
                console.log(i)
            }
            await web3.eth.sendTransaction({
                to: accounts[0],
                from: accounts[8],
                value: 1,
                gasLimit: 270000
            });
        }

        let oldCount = (await voting.getProposalsNum()).toString();
        await voting.proposalSubmit("Second one", "This is second proposal!", BigInt(1000000 * 10 ** 18).toString(10), accounts[7], {value: 10 * 10 ** 18});
        let newCount = (await voting.getProposalsNum()).toString();

        assert.ok( parseInt(newCount) === parseInt(oldCount) + 1, "Proposal count wrong");
    });

    it ('Try to vote (success)', async() => {
        let proposal = await voting.proposals(0);
        let yesBefore = parseInt(proposal.voteNumYes.toString());
        let noBefore = parseInt(proposal.voteNumNo.toString());

        await emmSharedNodes.vote(1, 1);

        let proposalAfterFail = await voting.proposals(0);
        let yesAfterFail = parseInt(proposalAfterFail.voteNumYes.toString());
        let noAfterFail = parseInt(proposalAfterFail.voteNumNo.toString());

        assert.ok(yesBefore === yesAfterFail, "Yes shouldn't change");
        assert.ok(noBefore === noAfterFail, "No shouldn't change");
    })

});
