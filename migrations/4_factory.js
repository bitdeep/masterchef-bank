// truffle migrate --f 4 --to 4 --network dev
const UniswapV2Factory = artifacts.require('UniswapV2Factory');
const UniswapV2Pair = artifacts.require('UniswapV2Pair');
module.exports = async function (deployer, network, accounts) {
    await deployer.deploy(UniswapV2Factory);
    const _factory = await UniswapV2Factory.deployed();
    console.log(network, 'FACTORY_ADDRESS', _factory.address);
    await _factory.setFeeTo(accounts[0]);
    const r = await _factory.pairCodeHash();
    const pairCodeHash = await _factory.pairCodeHash();
    console.log('INIT_CODE_HASH local:', r);
    console.log('INIT_CODE_HASH:', pairCodeHash);

};
