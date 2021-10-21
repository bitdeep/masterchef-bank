const chalk = require('chalk');
const {accounts, contract} = require('@openzeppelin/test-environment');
const {BN, expectRevert, time, expectEvent, constants} = require('@openzeppelin/test-helpers');
const {expect} = require('chai');
const HermesHeroes = contract.fromArtifact('HermesHeroes');
const FaucetERC20 = contract.fromArtifact('FaucetERC20');
const MasterChef = contract.fromArtifact('MasterChef');
const Bank = contract.fromArtifact('Bank2');
const ApolloToken = contract.fromArtifact('ApolloToken');
const WSDN = contract.fromArtifact("WSDN");
const IUniswapV2Pair = contract.fromArtifact("IUniswapV2Pair");
const UniswapV2Factory = contract.fromArtifact("UniswapV2Factory");
const UniswapV2Router02 = contract.fromArtifact("UniswapV2Router02");

let yellowBright = chalk.yellowBright;
let magenta = chalk.magenta;
let cyan = chalk.cyan;
let yellow = chalk.yellow;
let red = chalk.red;
let blue = chalk.blue;

function now() {
    return parseInt((new Date().getTime()) / 1000);
}

function hours(total) {
    return parseInt(60 * 60 * total);
}

function fromWei(v) {
    return web3.utils.fromWei(v, 'ether').toString();
}

function toWei(v) {
    return web3.utils.toWei(v).toString();
}

const mintAmount = '100';
const MINTED = toWei(mintAmount);
let eggPerBlock;
const DEAD_ADDR = '0x000000000000000000000000000000000000dEaD';
let dev, user, feeAddress, reserve;
const ONE = toWei('1');

describe('Bank', async function () {
    beforeEach(async function () {
        this.timeout(60000);
        dev = accounts[0];
        user = accounts[1];
        devaddr = accounts[2];
        feeAddress = accounts[3];
        reserve = accounts[4];

        this.weth = await WSDN.new({from: dev});
        this.factory = await UniswapV2Factory.new({from: dev});
        this.router = await UniswapV2Router02.new({from: dev});
        await this.router.init(this.factory.address, this.weth.address, {from: dev});

        eggPerBlock = web3.utils.toWei('1');

        this.IRON = await FaucetERC20.new("IRON", "IRON", MINTED, {from: dev});
        this.nft = await HermesHeroes.new(this.IRON.address, {from: dev});

        this.Apollo = await ApolloToken.new({from: dev});
        await this.Apollo.mint(dev, MINTED, {from: dev});
        this.farm = await MasterChef.new(this.Apollo.address, 0,
            devaddr, feeAddress, this.nft.address, {from: dev});
        await this.Apollo.setMinter(this.farm.address, true, {from: dev});


        await this.factory.createPair(this.IRON.address, this.Apollo.address);
        this.pairAddr = await this.factory.getPair(this.IRON.address, this.Apollo.address);
        this.pair = await IUniswapV2Pair.at(this.pairAddr);

        await this.IRON.approve(this.router.address, MINTED, {from: dev});
        await this.Apollo.approve(this.router.address, MINTED, {from: dev});
        await this.router.addLiquidity(this.IRON.address, this.Apollo.address, ONE, ONE,
            0, 0, dev, now(), {from: dev});

    });
    describe('MasterChef', async function () {

        it('farm without nft', async function () {
            this.timeout(60000);
            // await this.IRON.mint(toWei('1000'), {from: dev});
            // await this.IRON.approve(this.nft.address, toWei('1000'), {from: dev});
            // await this.nft.unpause({from: dev});
            // await this.nft.buy('1', {from: dev});

            let balanceOfLpDev = (await this.pair.balanceOf(dev));
            console.log('balanceOfLpDev', fromWei(balanceOfLpDev));
            await this.farm.add('1', this.pairAddr, '0', {from: dev});
            await this.pair.approve(this.farm.address, MINTED, {from: dev});
            await this.farm.deposit('0', balanceOfLpDev, {from: dev});
            console.log('balanceOfLpDev', fromWei( (await this.pair.balanceOf(dev)) ));

            await this.farm.withdraw('0', balanceOfLpDev, {from: dev});
            console.log('balanceOfLpDev', fromWei( (await this.pair.balanceOf(dev)) ));
            console.log('balanceOfApolloDev', fromWei( (await this.Apollo.balanceOf(dev)) ));

            // await time.increase(hours(73));
            // await time.advanceBlock();

        });

        it('farm with nft', async function () {
            this.timeout(60000);
            await this.IRON.mint(toWei('1000'), {from: dev});
            await this.IRON.approve(this.nft.address, toWei('1000'), {from: dev});
            await this.nft.unpause({from: dev});
            await this.nft.buy('5', {from: dev});
            const balanceOfNft = await this.nft.balanceOf(dev);
            const isNftHolder = await this.farm.isNftHolder(dev);
            const calculateBonus = await this.farm.calculateBonus(dev);
            console.log('balanceOfNft', balanceOfNft.toString());
            console.log('isNftHolder', isNftHolder);
            console.log('calculateBonus', calculateBonus.toString());

            let balanceOfLpDev = (await this.pair.balanceOf(dev));
            console.log('balanceOfLpDev', fromWei(balanceOfLpDev));
            await this.farm.add('1', this.pairAddr, '0', {from: dev});
            await this.pair.approve(this.farm.address, MINTED, {from: dev});
            await this.farm.deposit('0', balanceOfLpDev, {from: dev});
            console.log('balanceOfLpDev', fromWei( (await this.pair.balanceOf(dev)) ));

            await this.farm.withdraw('0', balanceOfLpDev, {from: dev});
            console.log('balanceOfLpDev', fromWei( (await this.pair.balanceOf(dev)) ));
            console.log('balanceOfApolloDev', fromWei( (await this.Apollo.balanceOf(dev)) ));

            // await time.increase(hours(73));
            // await time.advanceBlock();

        });

    });


});
