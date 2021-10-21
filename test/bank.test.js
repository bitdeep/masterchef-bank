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
const numeral = require('numeral');

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

function d(v) {
    return numeral( v.toString() ).format('0,0');
}

function toWei(v) {
    return web3.utils.toWei(v).toString();
}

const mintAmount = '1000';
const MINTED = toWei(mintAmount);
let eggPerBlock;
const DEAD_ADDR = '0x000000000000000000000000000000000000dEaD';
let dev, user, feeAddress, reserve;
const ONE = toWei('1');
const TWO = toWei('2');
const CEM = toWei('100');

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
        await this.Apollo.mint(user, MINTED, {from: dev});

        this.farm = await MasterChef.new(this.Apollo.address, 0,
            devaddr, feeAddress, this.nft.address, {from: dev});
        await this.Apollo.setMinter(this.farm.address, true, {from: dev});

        await this.factory.createPair(this.IRON.address, this.Apollo.address);
        this.pairAddr = await this.factory.getPair(this.IRON.address, this.Apollo.address);
        this.pair = await IUniswapV2Pair.at(this.pairAddr);

        await this.IRON.approve(this.router.address, MINTED, {from: dev});
        await this.Apollo.approve(this.router.address, MINTED, {from: dev});
        await this.Apollo.approve(this.router.address, MINTED, {from: user});

        await this.router.addLiquidity(this.IRON.address, this.Apollo.address, CEM, CEM,
            0, 0, dev, now()+60, {from: dev});

        await this.Apollo.setSwapToken(this.IRON.address, {from: dev});
        await this.Apollo.updateSwapRouter(this.router.address, {from: dev});

        this.bank = await Bank.new(
            this.Apollo.address,
            this.IRON.address,
            this.weth.address,
            this.router.address, {from: dev});

        await this.Apollo.setBank(this.bank.address, {from: dev});
        await this.Apollo.setMasterchef(this.farm.address, {from: dev});
        await this.Apollo.updateSwapAndLiquifyEnabled(true, {from: dev});

    });
    describe('Bank2', async function () {

        it('manual repo', async function () {
            this.timeout(60000);
            const balanceOfDev = await this.IRON.balanceOf(dev);
            console.log('balanceOfDev', fromWei(balanceOfDev));
            const getTime = await this.bank.getTime();
            const n1 = parseInt(getTime.toString())+60;
            const day = hours(24);
            const treeDays = hours(72)
            const n2 = n1 + treeDays;
            console.log('getTime', n1, n2);

            await this.bank.addpool('0', n1, n2,
                this.Apollo.address, this.router.address, {from: dev});
            await this.bank.start(treeDays, {from: dev});

            await this.router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                ONE, 0, [this.Apollo.address, this.IRON.address], dev, n1, {from: user});

            let balanceOfToken = await this.Apollo.balanceOf(this.Apollo.address);
            let balanceOfBank = await this.Apollo.balanceOf(this.bank.address);
            console.log('balanceOfToken', fromWei(balanceOfToken) );
            console.log('balanceOfBank', fromWei(balanceOfBank) );
            await time.increase(hours(1));
            await time.advanceBlock();

            await this.Apollo.transfer(reserve, TWO, {from: user});

            const balanceOfReserve = await this.Apollo.balanceOf(reserve);
            balanceOfToken = await this.Apollo.balanceOf(this.Apollo.address);
            balanceOfBank = await this.IRON.balanceOf(this.bank.address);
            console.log('balanceOfReserve', fromWei(balanceOfReserve) );
            console.log('balanceOfToken', fromWei(balanceOfToken) );
            console.log('balanceOfBank', fromWei(balanceOfBank) );

            // await this.bank.enroll(0, {from: dev});
            // await this.bank.enroll(0, {from: user});
            // await this.bank.enroll(0, {from: reserve});

            await this.Apollo.approve(this.bank.address, CEM, {from: dev});
            await this.Apollo.approve(this.bank.address, CEM, {from: user});

            await this.Apollo.approve(this.bank.address, CEM, {from: reserve});
            await this.bank.deposit(CEM, {from: dev});

            console.log('1 balanceOfReserve', fromWei(await this.Apollo.balanceOf(reserve)) );
            await this.bank.deposit(ONE, {from: reserve});
            await this.bank.deposit(ONE, {from: user});

            await time.increase(hours(24));
            await time.advanceBlock();


            await this.bank.compound({from: dev});

            console.log('2 balanceOfReserve', fromWei(await this.Apollo.balanceOf(reserve)) );

            let pendingIRON = await this.bank.pendingIRON(dev);
            console.log('pendingIRON', fromWei(pendingIRON) );

        });

        /*
        it('repo via token transfers', async function () {
            this.timeout(60000);
            const balanceOfDev = await this.IRON.balanceOf(dev);
            console.log('balanceOfDev', fromWei(balanceOfDev));
            const getTime = await this.bank.getTime();
            const n1 = parseInt(getTime.toString())+60;
            const day = hours(24);
            const treeDays = hours(72)
            const n2 = n1 + treeDays;
            console.log('getTime', n1, n2);

            await this.bank.addpool('0', n1, n2,
                this.Apollo.address, this.router.address, {from: dev});
            await this.bank.start(treeDays, {from: dev});

            await this.router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                ONE, 0, [this.Apollo.address, this.IRON.address], dev, n1, {from: user});

            let balanceOfToken = await this.Apollo.balanceOf(this.Apollo.address);
            let balanceOfBank = await this.Apollo.balanceOf(this.bank.address);
            console.log('balanceOfToken', fromWei(balanceOfToken) );
            console.log('balanceOfBank', fromWei(balanceOfBank) );
            await time.increase(hours(1));
            await time.advanceBlock();

            await this.Apollo.transfer(reserve, TWO, {from: user});

            const balanceOfReserve = await this.Apollo.balanceOf(reserve);
            balanceOfToken = await this.Apollo.balanceOf(this.Apollo.address);
            balanceOfBank = await this.IRON.balanceOf(this.bank.address);
            console.log('balanceOfReserve', fromWei(balanceOfReserve) );
            console.log('balanceOfToken', fromWei(balanceOfToken) );
            console.log('balanceOfBank', fromWei(balanceOfBank) );

            // await this.bank.enroll(0, {from: dev});
            // await this.bank.enroll(0, {from: user});
            // await this.bank.enroll(0, {from: reserve});

            await this.Apollo.approve(this.bank.address, CEM, {from: dev});
            await this.Apollo.approve(this.bank.address, CEM, {from: user});

            await this.Apollo.approve(this.bank.address, CEM, {from: reserve});
            await this.bank.deposit(CEM, {from: dev});

            console.log('1 balanceOfReserve', fromWei(await this.Apollo.balanceOf(reserve)) );
            await this.bank.deposit(ONE, {from: reserve});
            await this.bank.deposit(ONE, {from: user});

            await time.increase(hours(24));
            await time.advanceBlock();


            await this.bank.compound({from: dev});

            console.log('2 balanceOfReserve', fromWei(await this.Apollo.balanceOf(reserve)) );

            let pendingIRON = await this.bank.pendingIRON(dev);
            console.log('pendingIRON', fromWei(pendingIRON) );

        });
        */
    });


});
