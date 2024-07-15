import { artifacts, contract, ethers, network } from "hardhat";
import { time, BN, expectEvent, expectRevert } from "@openzeppelin/test-helpers";
import { parseEther, formatEther } from "ethers/lib/utils";
import { expect } from "chai";
import { beforeEach } from "mocha";
import { BigNumber } from "ethers";

import ERC20MockArtifact from "./artifactsFile/ERC20Mock.json";
import CakeTokenArtifact from "./artifactsFile/CakeToken.json";
import SyrupBarArtifact from "./artifactsFile/SyrupBar.json";
import MasterChefArtifact from "./artifactsFile/MasterChef.json";
import MasterChefV2Artifact from "./artifactsFile/MasterChefV2.json";
import CakePoolArtifact from "./artifactsFile/CakePool.json";
import VECakeArtifact from "./artifactsFile/VECakeTest.json";
import ProxyForCakePoolArtifact from "./artifactsFile/ProxyForCakePool.json";
import ProxyForCakePoolFactoryArtifact from "./artifactsFile/ProxyForCakePoolFactory.json";
import DelegatorArtifact from "./artifactsFile/Delegator.json";
import MockBunniesArtifact from "./artifactsFile/MockBunnies.json";
import PancakeProfileArtifact from "./artifactsFile/PancakeProfile.json";
import PancakeProfileProxyV2Artifact from "./artifactsFile/PancakeProfileProxyV2.json";
import VECakeProxyArtifact from "../artifacts/contracts/VECakeProxy.sol/VECakeProxy.json";
import IFODeployerV8Artifact from "./artifactsFile/IFODeployerV8.json";
import LZEndpointMockArtifact from "./artifactsFile/LZEndpointMock.json";

const PancakeVeSender = artifacts.require("./PancakeVeSender.sol");
const PancakeVeReceiver = artifacts.require("./PancakeVeReceiver.sol");

const ZERO = BigNumber.from(0);
const DAY = BigNumber.from(86400);
const WEEK = DAY.mul(7);
const YEAR = DAY.mul(365);
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("VCakeProxy", () => {
    let ProxyForCakePoolFactorySC, masterChefV2, CakePoolSC, VECakeSC, VECakeProxySC, PancakeProfileSC, MockBunniesSC,
        PancakeProfileProxyV2SC, CakeTokenSC;
    let admin;
    let user1;
    let user2;
    let user3;
    let user4;
    let user5;
    let treasury;
    let redistributor;
    let ifoDeployerV8SC;
    let layerZeroEndpointMockSrc;
    let layerZeroEndpointMockDst;
    let pancakeVeSenderSC;
    let pancakeVeReceiverSC;

    // VARIABLES
    let chainIdSrc = 1;
    let chainIdDst = 2;

    before(async function () {
        [admin, user1, user2, user3, user4, user5, treasury, redistributor] = await ethers.getSigners();
    });

    beforeEach(async () => {
        const ERC20Mock = await ethers.getContractFactoryFromArtifact(ERC20MockArtifact);

        // deploy cake token
        const CakeToken = await ethers.getContractFactoryFromArtifact(CakeTokenArtifact);
        CakeTokenSC = await CakeToken.deploy();
        // mint cake for users
        await CakeTokenSC["mint(address,uint256)"](admin.address, ethers.utils.parseUnits("100000000000000"));
        await CakeTokenSC["mint(address,uint256)"](user1.address, ethers.utils.parseUnits("100000000"));
        await CakeTokenSC["mint(address,uint256)"](user2.address, ethers.utils.parseUnits("100000000"));
        await CakeTokenSC["mint(address,uint256)"](user3.address, ethers.utils.parseUnits("100000000"));
        await CakeTokenSC["mint(address,uint256)"](user4.address, ethers.utils.parseUnits("100000000"));

        // deploy SyrupBar
        const SyrupBar = await ethers.getContractFactoryFromArtifact(SyrupBarArtifact);
        const syrupBar = await SyrupBar.deploy(CakeTokenSC.address);

        // deploy MasterChef
        const MasterChef = await ethers.getContractFactoryFromArtifact(MasterChefArtifact);
        const masterChef = await MasterChef.deploy(
            CakeTokenSC.address,
            syrupBar.address,
            admin.address,
            ethers.utils.parseUnits("40"),
            ethers.constants.Zero
        );

        // transfer ownership to MasterChef
        await CakeTokenSC.transferOwnership(masterChef.address);
        await syrupBar.transferOwnership(masterChef.address);

        const lpTokenV1 = await ERC20Mock.deploy("LP Token V1", "LPV1");
        const dummyTokenV2 = await ERC20Mock.deploy("Dummy Token V2", "DTV2");

        // add pools in MasterChef
        await masterChef.add(0, lpTokenV1.address, true); // farm with pid 1 and 0 allocPoint
        await masterChef.add(1, dummyTokenV2.address, true); // farm with pid 2 and 1 allocPoint

        // deploy MasterChefV2
        const MasterChefV2 = await ethers.getContractFactoryFromArtifact(MasterChefV2Artifact);
        masterChefV2 = await MasterChefV2.deploy(masterChef.address, CakeTokenSC.address, 2, admin.address);

        await dummyTokenV2.mint(admin.address, ethers.utils.parseUnits("1000"));
        await dummyTokenV2.approve(masterChefV2.address, ethers.constants.MaxUint256);
        await masterChefV2.init(dummyTokenV2.address);

        const lpTokenV2 = await ERC20Mock.deploy("LP Token V2", "LPV2");
        const dummyTokenV3 = await ERC20Mock.deploy("Dummy Token V3", "DTV3");
        const dummyTokenForCakePool = await ERC20Mock.deploy("Dummy Token Cake Pool", "DTCP");
        const dummyTokenForSpecialPool2 = await ERC20Mock.deploy("Dummy Token Special pool 2", "DT");

        await masterChefV2.add(0, lpTokenV2.address, true, true); // regular farm with pid 0 and 1 allocPoint
        await masterChefV2.add(1, dummyTokenV3.address, true, true); // regular farm with pid 1 and 1 allocPoint
        await masterChefV2.add(1, dummyTokenForCakePool.address, false, true); // special farm with pid 2 and 1 allocPoint
        await masterChefV2.add(0, dummyTokenForSpecialPool2.address, false, true); // special farm with pid 3 and 0 allocPoint

        // deploy cake pool
        const CakePool = await ethers.getContractFactoryFromArtifact(CakePoolArtifact);
        CakePoolSC = await CakePool.deploy(
            CakeTokenSC.address,
            masterChefV2.address,
            admin.address,
            admin.address,
            admin.address,
            2
        );
        await masterChefV2.updateWhiteList(CakePoolSC.address, true);
        await dummyTokenForCakePool.mint(admin.address, ethers.utils.parseUnits("1000"));
        await dummyTokenForCakePool.approve(CakePoolSC.address, ethers.constants.MaxUint256);
        await CakePoolSC.init(dummyTokenForCakePool.address);

        //  approve cake for CakePoolSC
        await CakeTokenSC.connect(admin).approve(CakePoolSC.address, ethers.constants.MaxUint256);
        await CakeTokenSC.connect(user1).approve(CakePoolSC.address, ethers.constants.MaxUint256);
        await CakeTokenSC.connect(user2).approve(CakePoolSC.address, ethers.constants.MaxUint256);
        await CakeTokenSC.connect(user3).approve(CakePoolSC.address, ethers.constants.MaxUint256);
        await CakeTokenSC.connect(user4).approve(CakePoolSC.address, ethers.constants.MaxUint256);

        // deploy ProxyForCakePoolFactory
        const ProxyForCakePoolFactory = await ethers.getContractFactoryFromArtifact(ProxyForCakePoolFactoryArtifact);
        ProxyForCakePoolFactorySC = await ProxyForCakePoolFactory.deploy();

        // deploy VECake
        const VECake = await ethers.getContractFactoryFromArtifact(VECakeArtifact);
        VECakeSC = await VECake.deploy(CakePoolSC.address, CakeTokenSC.address, ProxyForCakePoolFactorySC.address);

        await CakeTokenSC.connect(admin).approve(VECakeSC.address, ethers.constants.MaxUint256);

        await ProxyForCakePoolFactorySC.initialize(VECakeSC.address);

        await CakePoolSC.setVCakeContract(VECakeSC.address);

        await VECakeSC.initializeCakePoolMigration();

        // lock cake in cake pool
        await CakePoolSC.connect(user1).deposit(ethers.utils.parseUnits("1000"), 3600 * 24 * 365);
        await CakePoolSC.connect(user2).deposit(ethers.utils.parseUnits("1000"), 3600 * 24 * 365);
        await CakePoolSC.connect(user3).deposit(ethers.utils.parseUnits("1000"), 3600 * 24 * 365);

        // deploy PancakeProfile
        const PancakeProfile = await ethers.getContractFactoryFromArtifact(PancakeProfileArtifact);
        PancakeProfileSC = await PancakeProfile.deploy(
            CakeTokenSC.address,
            parseEther("0"),
            parseEther("0"),
            parseEther("0")
        );

        // deploy MockBunnies
        const MockBunnies = await ethers.getContractFactoryFromArtifact(MockBunniesArtifact);
        MockBunniesSC = await MockBunnies.deploy();

        // add NFT address
        await PancakeProfileSC.addNftAddress(MockBunniesSC.address);

        // add team
        await PancakeProfileSC.addTeam("The Testers", "ipfs://hash/team1.json");

        let i = 0;
        for (let thisUser of [user1, user2, user3, user4, user5]) {
            // Mints a NFT
            await MockBunniesSC.connect(thisUser).mint();

            // Approves the contract to receive his NFT
            await MockBunniesSC.connect(thisUser).approve(PancakeProfileSC.address, i);

            // Creates the profile
            await PancakeProfileSC.connect(thisUser).createProfile("1", MockBunniesSC.address, i);
            i++;
        }

        // deploy sender and receiver
        const LZEndpointMock = await ethers.getContractFactoryFromArtifact(LZEndpointMockArtifact);
        layerZeroEndpointMockSrc = await LZEndpointMock.deploy(chainIdSrc);
        layerZeroEndpointMockDst = await LZEndpointMock.deploy(chainIdDst);
        pancakeVeSenderSC = await PancakeVeSender.new(VECakeSC.address, PancakeProfileSC.address, layerZeroEndpointMockSrc.address);
        pancakeVeReceiverSC = await PancakeVeReceiver.new(layerZeroEndpointMockDst.address);

        layerZeroEndpointMockSrc.setDestLzEndpoint(pancakeVeReceiverSC.address, layerZeroEndpointMockDst.address);
        layerZeroEndpointMockDst.setDestLzEndpoint(pancakeVeSenderSC.address, layerZeroEndpointMockSrc.address);

        // set each contracts source address, so it can send to each other
        await pancakeVeSenderSC.setTrustedRemote(
            chainIdDst,
            ethers.utils.solidityPack(["address", "address"], [pancakeVeReceiverSC.address, pancakeVeSenderSC.address])
        ); // for A, set B
        await pancakeVeReceiverSC.setTrustedRemote(
            chainIdSrc,
            ethers.utils.solidityPack(["address", "address"], [pancakeVeSenderSC.address, pancakeVeReceiverSC.address])
        ); // for B, set A

        await pancakeVeSenderSC.pause(true);

        // deploy IFODeployerV8.sol
        const IFODeployerV8 = await ethers.getContractFactoryFromArtifact(IFODeployerV8Artifact);
        ifoDeployerV8SC = await IFODeployerV8.deploy();

        // deploy PancakeProfileProxy.sol
        const PancakeProfileProxyV2 = await ethers.getContractFactoryFromArtifact(PancakeProfileProxyV2Artifact);
        PancakeProfileProxyV2SC = await PancakeProfileProxyV2.deploy(ifoDeployerV8SC.address, pancakeVeReceiverSC.address);

        // deploy VECakeSyncer.sol
        const VECakeProxy = await ethers.getContractFactoryFromArtifact(VECakeProxyArtifact);
        VECakeProxySC = await VECakeProxy.deploy();

        // update receiver address in VECakeSyncerSC
        await VECakeProxySC.connect(admin).updateReceiver(pancakeVeReceiverSC.address);

        // update proxies addresses
        await pancakeVeReceiverSC.updateProxyContract(VECakeProxySC.address, PancakeProfileProxyV2SC.address, {
            from: admin.address
        });

    });

    afterEach(async () => {
        await network.provider.send("hardhat_reset");
    });

    it("call pancakeVeSenderSC when paused should revert", async function () {
        await expectRevert(
            pancakeVeSenderSC.sendSyncMsg(chainIdDst, ethers.constants.AddressZero, false, false, 0, {
                from: admin.address
            }),
            "Pausable: paused");
    });

    describe("users migrate from cake pool", () => {
        beforeEach(async function () {

        });

        it("Migrated successfully", async function () {
            let userInfoOfUser2InCakePool = await CakePoolSC.userInfo(user2.address);

            let totalShares = await CakePoolSC.totalShares();
            let balanceOf = await CakePoolSC.balanceOf();
            // uint256 currentAmount = (balanceOf() * (user.shares)) / totalShares - user.userBoostedShare;
            let currentLockedBalanceOfUser2 = userInfoOfUser2InCakePool.shares
                .mul(balanceOf)
                .div(totalShares)
                .sub(userInfoOfUser2InCakePool.userBoostedShare)
                .sub(1);

            // migrate from cake pool
            await VECakeSC.connect(user2).migrateFromCakePool();

            let userInfoOfUser2InVECake = await VECakeSC.getUserInfo(user2.address);

            let ProxyForCakePool = await ethers.getContractFactoryFromArtifact(ProxyForCakePoolArtifact);
            let ProxyForCakePoolSC = await ProxyForCakePool.attach(userInfoOfUser2InVECake.cakePoolProxy);

            let cakePoolUser = await ProxyForCakePoolSC.cakePoolUser();

            expect(cakePoolUser).to.deep.eq(user2.address);
            expect(userInfoOfUser2InVECake.amount).to.deep.eq(ZERO);
            expect(userInfoOfUser2InVECake.end).to.deep.eq(ZERO);
            expect(userInfoOfUser2InVECake.cakePoolType).to.deep.eq(1);
            expect(userInfoOfUser2InVECake.withdrawFlag).to.deep.eq(0);
            expect(userInfoOfUser2InCakePool.lockEndTime).to.deep.eq(userInfoOfUser2InVECake.lockEndTime);

            expect(currentLockedBalanceOfUser2).to.deep.eq(userInfoOfUser2InVECake.cakeAmount);

            let proxyLockedBalanceOfUser2 = await VECakeSC.locks(userInfoOfUser2InVECake.cakePoolProxy);

            expect(proxyLockedBalanceOfUser2.amount).to.deep.eq(userInfoOfUser2InVECake.cakeAmount);
            expect(proxyLockedBalanceOfUser2.end).to.deep.eq(
                BigNumber.from(userInfoOfUser2InVECake.lockEndTime).div(WEEK).mul(WEEK)
            );

            // un-pause
            await pancakeVeSenderSC.pause(false, {
                from: admin.address
            });

            // sendSyncMsg
            await pancakeVeSenderSC.sendSyncMsg(
                chainIdDst,
                user2.address,
                true,
                true,
                0,
                {
                    from: user2.address,
                    value: ethers.utils.parseEther("0.05")
                }
            );

            let syncerLockedBalanceOfUser2 = await VECakeProxySC.locks(userInfoOfUser2InVECake.cakePoolProxy);
            expect(proxyLockedBalanceOfUser2.amount).to.deep.eq(syncerLockedBalanceOfUser2.amount);
            expect(proxyLockedBalanceOfUser2.end).to.deep.eq(syncerLockedBalanceOfUser2.end);
            let balanceOfUser2After = await VECakeSC.balanceOf(user2.address);
            let syncerBalanceOfUser2After = await VECakeProxySC.balanceOf(user2.address);
            expect(syncerBalanceOfUser2After).to.deep.eq(balanceOfUser2After);
        });
    });

    describe("Normal user lock cake in VECake", () => {
        beforeEach(async function () {

        });

        it("Create lock", async function () {
            await CakeTokenSC.connect(user4).approve(VECakeSC.address, ethers.constants.MaxUint256);

            let now = (await time.latest()).toString();
            let OneYear = BigNumber.from(now).add(YEAR);

            await VECakeSC.connect(user4).createLock(ethers.utils.parseUnits("1000"), OneYear);

            let userInfoOfUser4InVECake = await VECakeSC.getUserInfo(user4.address);

            expect(userInfoOfUser4InVECake.amount).to.deep.eq(ethers.utils.parseUnits("1000"));

            expect(userInfoOfUser4InVECake.end).to.deep.eq(OneYear.div(WEEK).mul(WEEK));

            // un-pause
            await pancakeVeSenderSC.pause(false, {
                from: admin.address
            });

            // sendSyncMsg
            await pancakeVeSenderSC.sendSyncMsg(
                chainIdDst,
                user4.address,
                true,
                true,
                0,
                {
                    from: user4.address,
                    value: ethers.utils.parseEther("0.05")
                }
            );

            let syncerLockedBalanceOfUser4 = await VECakeProxySC.locks(user4.address);
            expect(userInfoOfUser4InVECake.amount).to.deep.eq(syncerLockedBalanceOfUser4.amount);
            expect(userInfoOfUser4InVECake.end).to.deep.eq(syncerLockedBalanceOfUser4.end);
            let balanceOfUser4After = await VECakeSC.balanceOf(user4.address);
            let syncerBalanceOfUser4After = await VECakeProxySC.balanceOf(user4.address);
            expect(syncerBalanceOfUser4After).to.deep.eq(balanceOfUser4After);
        });

        it("Create lock without sync profile", async function () {
            await CakeTokenSC.connect(user3).approve(VECakeSC.address, ethers.constants.MaxUint256);

            // Creates the profile
            await PancakeProfileSC.connect(user3).pauseProfile();

            let now = (await time.latest()).toString();
            let OneYear = BigNumber.from(now).add(YEAR);

            await VECakeSC.connect(user3).createLock(ethers.utils.parseUnits("1000"), OneYear);

            let userInfoOfUser3InVECake = await VECakeSC.getUserInfo(user3.address);

            expect(userInfoOfUser3InVECake.amount).to.deep.eq(ethers.utils.parseUnits("1000"));

            expect(userInfoOfUser3InVECake.end).to.deep.eq(OneYear.div(WEEK).mul(WEEK));

            // un-pause
            await pancakeVeSenderSC.pause(false, {
                from: admin.address
            });

            // sendSyncMsg
            await pancakeVeSenderSC.sendSyncMsg(
                chainIdDst,
                user3.address,
                true,
                false,
                0,
                {
                    from: user3.address,
                    value: ethers.utils.parseEther("0.05")
                }
            );

            let syncerLockedBalanceOfUser3 = await VECakeProxySC.locks(user3.address);
            expect(userInfoOfUser3InVECake.amount).to.deep.eq(syncerLockedBalanceOfUser3.amount);
            expect(userInfoOfUser3InVECake.end).to.deep.eq(syncerLockedBalanceOfUser3.end);
            let balanceOfUser3After = await VECakeSC.balanceOf(user3.address);
            let syncerBalanceOfUser3After = await VECakeProxySC.balanceOf(user3.address);
            expect(syncerBalanceOfUser3After).to.deep.eq(balanceOfUser3After);
        });

        it("Increase Lock Amount", async function () {
            await CakeTokenSC.connect(user4).approve(VECakeSC.address, ethers.constants.MaxUint256);

            let now = (await time.latest()).toString();
            let OneYear = BigNumber.from(now).add(YEAR);

            await VECakeSC.connect(user4).createLock(ethers.utils.parseUnits("1000"), OneYear);

            // un-pause
            await pancakeVeSenderSC.pause(false, {
                from: admin.address
            });

            // sendSyncMsg
            await pancakeVeSenderSC.sendSyncMsg(
                chainIdDst,
                user4.address,
                true,
                true,
                0,
                {
                    from: user4.address,
                    value: ethers.utils.parseEther("0.05")
                }
            );

            let userInfoOfUser4InVECakeBefore = await VECakeSC.getUserInfo(user4.address);

            await VECakeSC.connect(user4).increaseLockAmount(ethers.utils.parseUnits("66.66"));

            let userInfoOfUser4InVECakeAfter = await VECakeSC.getUserInfo(user4.address);

            expect(userInfoOfUser4InVECakeAfter.amount.sub(userInfoOfUser4InVECakeBefore.amount)).to.deep.eq(
                ethers.utils.parseUnits("66.66")
            );

            // sendSyncMsg
            await pancakeVeSenderSC.sendSyncMsg(
                chainIdDst,
                user4.address,
                true,
                true,
                0,
                {
                    from: user4.address,
                    value: ethers.utils.parseEther("0.05")
                }
            );

            let syncerLockedBalanceOfUser4 = await VECakeProxySC.locks(user4.address);
            expect(userInfoOfUser4InVECakeAfter.amount).to.deep.eq(syncerLockedBalanceOfUser4.amount);
            let balanceOfUser4After = await VECakeSC.balanceOf(user4.address);
            let syncerBalanceOfUser4After = await VECakeProxySC.balanceOf(user4.address);
            expect(syncerBalanceOfUser4After).to.deep.eq(balanceOfUser4After);
        });

        it("Increase Unlock Time", async function () {
            await CakeTokenSC.connect(user4).approve(VECakeSC.address, ethers.constants.MaxUint256);

            let now = (await time.latest()).toString();
            let OneYear = BigNumber.from(now).add(YEAR);

            await VECakeSC.connect(user4).createLock(ethers.utils.parseUnits("1000"), OneYear);

            await time.increase(YEAR.div(2).toNumber());

            let newUnlockTime = OneYear.add(YEAR.div(2));

            await VECakeSC.connect(user4).increaseUnlockTime(newUnlockTime);

            let userInfoOfUser4InVECake = await VECakeSC.getUserInfo(user4.address);

            expect(userInfoOfUser4InVECake.end).to.deep.eq(newUnlockTime.div(WEEK).mul(WEEK));

            // un-pause
            await pancakeVeSenderSC.pause(false, {
                from: admin.address
            });

            // sendSyncMsg
            await pancakeVeSenderSC.sendSyncMsg(
                chainIdDst,
                user4.address,
                true,
                true,
                0,
                {
                    from: user4.address,
                    value: ethers.utils.parseEther("0.05")
                }
            );

            let syncerLockedBalanceOfUser4 = await VECakeProxySC.locks(user4.address);
            expect(userInfoOfUser4InVECake.end).to.deep.eq(syncerLockedBalanceOfUser4.end);
            let balanceOfUser4After = await VECakeSC.balanceOf(user4.address);
            let syncerBalanceOfUser4After = await VECakeProxySC.balanceOf(user4.address);
            expect(syncerBalanceOfUser4After).to.deep.eq(balanceOfUser4After);
        });
    });

    describe("withdraw", () => {
        beforeEach(async function () {

        });

        it("Withdraw after lock expired", async function () {
            await CakeTokenSC.connect(user4).approve(VECakeSC.address, ethers.constants.MaxUint256);

            let now = (await time.latest()).toString();
            //let  LockPeriod = BigNumber.from(now).add(YEAR);
            //let  LockPeriod = BigNumber.from(now).add(YEAR.add(YEAR).add(YEAR).add(YEAR));
            let  LockPeriod = BigNumber.from(now).add(WEEK).add(WEEK);

            await VECakeSC.connect(user4).createLock(ethers.utils.parseUnits("1000"), LockPeriod);

            // un-pause
            await pancakeVeSenderSC.pause(false, {
                from: admin.address
            });

            // sendSyncMsg
            await pancakeVeSenderSC.sendSyncMsg(
                chainIdDst,
                user4.address,
                true,
                true,
                0,
                {
                    from: user4.address,
                    value: ethers.utils.parseEther("0.05")
                }
            );

            await time.increaseTo(LockPeriod.add(WEEK).toNumber());

            let cakeBalanceBeforeOfUser4 = await CakeTokenSC.balanceOf(user4.address);

            await VECakeSC.connect(user4).withdrawAll(user4.address);

            await time.increase(10);

            let cakeBalanceAfterOfUser4 = await CakeTokenSC.balanceOf(user4.address);

            let userInfoOfUser4InVECake = await VECakeSC.getUserInfo(user4.address);
            expect(cakeBalanceAfterOfUser4.sub(cakeBalanceBeforeOfUser4)).to.deep.eq(ethers.utils.parseUnits("1000"));
            expect(userInfoOfUser4InVECake.amount).to.deep.eq(ZERO);
            expect(userInfoOfUser4InVECake.end).to.deep.eq(ZERO);

            let balanceOfUser4 = await VECakeSC.balanceOf(user4.address);
            let syncerBalanceOfUser4 = await VECakeProxySC.balanceOf(user4.address);
            expect(syncerBalanceOfUser4).to.deep.eq(balanceOfUser4);

            console.log('#############################  WITHDRAW ALL  #############################');

            // // sendSyncMsg
            // await pancakeVeSenderSC.sendSyncMsg(
            //     chainIdDst,
            //     user4.address,
            //     true,
            //     true,
            //     0,
            //     {
            //         from: user4.address,
            //         value: ethers.utils.parseEther("0.05")
            //     }
            // );

            // let syncerLockedBalanceOfUser4 = await VECakeProxySC.locks(user4.address);
            // expect(userInfoOfUser4InVECake.amount).to.deep.eq(syncerLockedBalanceOfUser4.amount);

            let now1 = (await time.latest()).toString();
            //let LockPeriod1 = BigNumber.from(now1).add(YEAR);
            let LockPeriod1 = BigNumber.from(now1).add(WEEK).add(WEEK);

            await VECakeSC.connect(user4).createLock(ethers.utils.parseUnits("500"), LockPeriod1);

            let userInfoOfUser4InVECakeAfter = await VECakeSC.getUserInfo(user4.address);

            expect(userInfoOfUser4InVECakeAfter.amount).to.deep.eq(ethers.utils.parseUnits("500"));

            // sendSyncMsg
            await pancakeVeSenderSC.sendSyncMsg(
                chainIdDst,
                user4.address,
                true,
                true,
                600000,
                {
                    from: user4.address,
                    value: ethers.utils.parseEther("0.05")
                }
            );

            let syncerLockedBalanceOfUser4After = await VECakeProxySC.locks(user4.address);
            expect(userInfoOfUser4InVECakeAfter.amount).to.deep.eq(syncerLockedBalanceOfUser4After.amount);
            let balanceOfUser4After = await VECakeSC.balanceOf(user4.address);
            let syncerBalanceOfUser4After = await VECakeProxySC.balanceOf(user4.address);
            expect(syncerBalanceOfUser4After).to.deep.eq(balanceOfUser4After);
        });
    });

});