import { artifacts, contract, deployments, ethers, network } from "hardhat";
import { time, BN, expectEvent, expectRevert } from "@openzeppelin/test-helpers";
import { parseEther, formatEther } from "ethers/lib/utils";
import { expect } from "chai";
import { beforeEach } from "mocha";
import {BigNumber, Contract, ContractFactory} from "ethers";

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

const ZERO = BigNumber.from(0);
const DAY = BigNumber.from(86400);
const WEEK = DAY.mul(7);
const YEAR = DAY.mul(365);
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("VeCakeProxyV2", () => {
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
    let EndpointV2Mock: ContractFactory;
    let PancakeVeSenderV2: ContractFactory;
    let PancakeVeReceiverV2: ContractFactory;
    let pancakeVeSenderV2SC: Contract;
    let pancakeVeReceiverV2SC: Contract;

    // Constant representing a mock Endpoint ID for testing purposes
    const eidA = 1
    const eidB = 2

    before(async function () {
        [admin, user1, user2, user3, user4, user5, treasury, redistributor] = await ethers.getSigners();

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

        // The EndpointV2Mock contract comes from @layerzerolabs/test-devtools-evm-hardhat package
        // and its artifacts are connected as external artifacts to this project
        //
        // Unfortunately, hardhat itself does not yet provide a way of connecting external artifacts,
        // so we rely on hardhat-deploy to create a ContractFactory for EndpointV2Mock
        //
        // See https://github.com/NomicFoundation/hardhat/issues/1040
        const EndpointV2MockArtifact = await deployments.getArtifact('EndpointV2Mock');
        EndpointV2Mock = new ContractFactory(EndpointV2MockArtifact.abi, EndpointV2MockArtifact.bytecode, admin);

        // Deploying a mock LZ EndpointV2 with the given Endpoint ID
        layerZeroEndpointMockSrc = await EndpointV2Mock.deploy(eidA);
        layerZeroEndpointMockDst = await EndpointV2Mock.deploy(eidB);

        PancakeVeSenderV2 = await ethers.getContractFactory('PancakeVeSenderV2');
        PancakeVeReceiverV2 = await ethers.getContractFactory('PancakeVeReceiverV2');

        pancakeVeSenderV2SC = await PancakeVeSenderV2.deploy(VECakeSC.address, PancakeProfileSC.address, layerZeroEndpointMockSrc.address, admin.address);
        pancakeVeReceiverV2SC = await PancakeVeReceiverV2.deploy(layerZeroEndpointMockDst.address, admin.address);

        // Setting destination endpoints in the LZEndpoint mock for each MyOApp instance
        await layerZeroEndpointMockSrc.setDestLzEndpoint(pancakeVeReceiverV2SC.address, layerZeroEndpointMockDst.address);
        await layerZeroEndpointMockDst.setDestLzEndpoint(pancakeVeSenderV2SC.address, layerZeroEndpointMockSrc.address);

        // Setting each MyOApp instance as a peer of the other
        await pancakeVeSenderV2SC.connect(admin).setPeer(eidB, ethers.utils.zeroPad(pancakeVeReceiverV2SC.address, 32))
        await pancakeVeReceiverV2SC.connect(admin).setPeer(eidA, ethers.utils.zeroPad(pancakeVeSenderV2SC.address, 32))

        // deploy IFODeployerV8.sol
        const IFODeployerV8 = await ethers.getContractFactoryFromArtifact(IFODeployerV8Artifact);
        ifoDeployerV8SC = await IFODeployerV8.deploy();

        // deploy PancakeProfileProxy.sol
        const PancakeProfileProxyV2 = await ethers.getContractFactoryFromArtifact(PancakeProfileProxyV2Artifact);
        PancakeProfileProxyV2SC = await PancakeProfileProxyV2.deploy(ifoDeployerV8SC.address, pancakeVeReceiverV2SC.address);

        // deploy VECakeSyncer.sol
        const VECakeProxy = await ethers.getContractFactoryFromArtifact(VECakeProxyArtifact);
        VECakeProxySC = await VECakeProxy.deploy();

        // update receiver address in VECakeSyncerSC
        await VECakeProxySC.connect(admin).updateReceiver(pancakeVeReceiverV2SC.address);

        // update proxies addresses
        await pancakeVeReceiverV2SC.connect(admin).updateProxyContract(VECakeProxySC.address, PancakeProfileProxyV2SC.address);
    });

    // afterEach(async () => {
    //     await network.provider.send("hardhat_reset");
    // });

    describe("external test", () => {
        beforeEach(async function () {

        });

        it("userA lock for ", async function () {
            await CakeTokenSC.connect(user1).approve(VECakeSC.address, ethers.constants.MaxUint256);
            await CakeTokenSC.connect(user2).approve(VECakeSC.address, ethers.constants.MaxUint256);

            let now1 = (await time.latest()).toString();
            //let  LockPeriod1 = BigNumber.from(now).add(YEAR);
            let LockPeriod1 = BigNumber.from(now1).add(YEAR).add(YEAR);

            await VECakeSC.connect(user1).createLock(ethers.utils.parseUnits("1000"), LockPeriod1);

            // Define native fee and quote for the message send operation
            let nativeFee1 = 0;
            ;[nativeFee1] = await pancakeVeSenderV2SC.connect(user1).getEstimateGasFees(eidB, 0);
            console.log('nativeFee1: ', nativeFee1);
            // sendSyncMsg
            await pancakeVeSenderV2SC.connect(user1).sendSyncMsg(
                eidB,
                user1.address,
                true,
                true,
                0,
                {
                    value: nativeFee1
                }
            );

            await time.increaseTo(LockPeriod1.add(WEEK).toNumber());

            await time.increase(10);

            await VECakeSC.connect(user1).withdrawAll(user1.address);

            console.log('#############################  WITHDRAW ALL  #############################');

            // // sendSyncMsg
            // await pancakeVeSenderSC.connect(user1).sendSyncMsg(
            //     eidB,
            //     user1.address,
            //     true,
            //     true,
            //     7900000,
            //     {
            //         value: ethers.utils.parseEther("0.5")
            //     }
            // );
            //
            // let userInfoOfUser1InVECake = await VECakeSC.getUserInfo(user1.address);
            // let syncerLockedBalanceOfUser1 = await VECakeProxySC.locks(user1.address);
            // expect(userInfoOfUser1InVECake.amount).to.deep.eq(syncerLockedBalanceOfUser1.amount);

            await time.increaseTo(LockPeriod1.add(YEAR).add(YEAR).toNumber());

            let now2 = (await time.latest()).toString();
            let LockPeriod2 = BigNumber.from(now2).add(WEEK.mul(100));

            await VECakeSC.connect(user2).createLock(ethers.utils.parseUnits("1000"), LockPeriod2);

            // Define native fee and quote for the message send operation
            let nativeFee2 = 0;
            ;[nativeFee2] = await pancakeVeSenderV2SC.connect(user2).getEstimateGasFees(eidB, 13500000);
            console.log('nativeFee2: ', nativeFee2);
            // sendSyncMsg
            await pancakeVeSenderV2SC.connect(user2).sendSyncMsg(
                eidB,
                user2.address,
                true,
                true,
                13500000,
                {
                    value: nativeFee2
                }
            );

            let userInfoOfUser2InVECake = await VECakeSC.getUserInfo(user2.address);
            let syncerLockedBalanceOfUser2 = await VECakeProxySC.locks(user2.address);
            expect(userInfoOfUser2InVECake.amount).to.deep.eq(syncerLockedBalanceOfUser2.amount);

            await time.increaseTo(LockPeriod2.toNumber());

            let now3 = (await time.latest()).toString();
            console.log(now3.toString());
        });

        it("userA re-lock for ", async function () {
            await CakeTokenSC.connect(user1).approve(VECakeSC.address, ethers.constants.MaxUint256);

            await time.increase(10);

            let now3 = (await time.latest()).toString();
            console.log(now3.toString());
            let LockPeriod3 = BigNumber.from(now3).add(WEEK);

            await VECakeSC.connect(user1).createLock(ethers.utils.parseUnits("1000"), LockPeriod3);

            // Define native fee and quote for the message send operation
            let nativeFee1 = 0;
            ;[nativeFee1] = await pancakeVeSenderV2SC.connect(user2).getEstimateGasFees(eidB, 0);
            console.log('nativeFee2: ', nativeFee1);
            // sendSyncMsg
            await pancakeVeSenderV2SC.connect(user1).sendSyncMsg(
                eidB,
                user1.address,
                true,
                true,
                0,
                {
                    value: nativeFee1
                }
            );

            let userInfoOfUser1InVECake = await VECakeSC.getUserInfo(user1.address);
            let syncerLockedBalanceOfUser1 = await VECakeProxySC.locks(user1.address);
            expect(userInfoOfUser1InVECake.amount).to.deep.eq(syncerLockedBalanceOfUser1.amount);
        });
    });
});

let address32 = ethers.utils.zeroPad('0x9D8A62E8Cf71ed1A5EbA53290A8b50C03c566c42', 32);
