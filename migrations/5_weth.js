// truffle migrate --f 5 --to 5 --network dev
const WSDN = artifacts.require('WSDN');
module.exports = async function(deployer, network, accounts) {
    await deployer.deploy(WSDN);
    const wmatic = await WSDN.deployed();
    console.log(network, 'WSDN', wmatic.address);
};
