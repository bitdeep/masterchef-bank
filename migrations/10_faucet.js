// truffle migrate --f 10 --to 10 --network dev
const FaucetERC20 = artifacts.require('FaucetERC20');
let deployer, network, accounts;
module.exports = async function (_deployer, _network, _accounts) {
    deployer = _deployer;
    network = _network;
    accounts = _accounts;
    const mint = web3.utils.toWei('1000000');
    await setup_faucet('Test', 'TT', mint);
};

async function setup_faucet(name, symbol, mint) {
    try {
        await deployer.deploy(FaucetERC20, name, symbol, mint);
        const faucet = await FaucetERC20.deployed();
        console.log(network, name, symbol, faucet.address);
    } catch (e) {
        console.error(network, name, symbol);
        console.error(e.toString());
        process.exit(1);
    }
}
