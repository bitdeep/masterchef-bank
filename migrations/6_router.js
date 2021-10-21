// truffle migrate --f 6 --to 6 --network dev
const UniswapV2Router02 = artifacts.require('UniswapV2Router02');
const UniswapV2Factory = artifacts.require('UniswapV2Factory');
const WSDN = artifacts.require('WSDN');
module.exports = async function (deployer, network, accounts) {
    const wsdn = await WSDN.deployed();
    const _factory = await UniswapV2Factory.deployed();
    await deployer.deploy(UniswapV2Router02);
    const router = await UniswapV2Router02.deployed();
    await router.init(_factory.address, wsdn.address);
    console.log(UniswapV2Router02.address, _factory.address, wsdn.address);
};
