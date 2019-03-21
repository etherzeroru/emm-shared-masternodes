let Masternode = artifacts.require("./Masternode.sol");

let masternodeContract;
let nodeId;

contract('Masternodes', (accounts) => {

    it('Deploy Masternode', async () => {
        masternodeContract = await Masternode.new();
        assert.isNotNull(masternodeContract);
    });

    it('Send Masternode Data to MN Contract', async () => {
        try {
            const tx = await web3.eth.sendTransaction({
                to: masternodeContract.address,
                from: accounts[0],
                value: BigInt(20000 * 10 ** 18).toString(10),
                gasLimit: 270000,
                data: '0x2f926732d853c35eee71c04a0403586a70c05d4d7866a81a826795cc1c8dff8a32646c72b81c634b04473192aa746a011a34d96cac4651cfc16847f88cee1189fc765877'
            });
            assert.isNotNull(tx);
        } catch (e) {
            console.log(e);
            assert.fail(e);
        }
    });
    it('Checking masternode created', async () => {
        nodeId = await masternodeContract.getId(accounts[0]);
        assert.isNotEmpty(nodeId)
    });

    it('Checking contract info', async () => {
        const info = await masternodeContract.getInfo(nodeId);
        assert.isNotEmpty(info);
        assert.equal(info[5], accounts[0]);
    });

    it('Processing withdraw', async () => {
        try {
            const wdTx = await web3.eth.sendTransaction({
                from: accounts[0],
                to: masternodeContract.address,
                gasLimit: 270000,
                value: 0
            });
            assert.isNotNull(wdTx);
        } catch (e) {
            console.log(e);
            assert.fail(e);
        }
    });

    it('Checking contract info after withdrawal', async () => {
        const info = await masternodeContract.getInfo(nodeId);
        assert.isNotEmpty(info);
        assert.equal('0x0000000000000000000000000000000000000000', info[5]);
    });

});
