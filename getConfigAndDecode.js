const ethers= require('ethers');

// Define provider
const provider = new ethers.providers.JsonRpcProvider('YOUR_RPC_PROVIDER_HERE');

// Define the smart contract address and ABI
// find endpoint address here: https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
const LzEndpointAddress = 'END_POINT_ADDRESS_HERE';
const LzEndpointABI = [
    'function getConfig(address _oapp, address _lib, uint32 _eid, uint32 _configType) external view returns (bytes memory config)',
];

// Create a contract instance
const contract = new ethers.Contract(LzEndpointAddress, LzEndpointABI, provider);

// Define the addresses and parameters
// find sendlib302 and receivelib302 addresses here: https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
const oappAddress = 'YOUR_OAPP_ADDRESS_HERE';
const sendLibAddress = 'SENDLIB302_ADDRESS_HERE';
const receiveLibAddress = 'RECEIVELIB302_ADDRESS_HERE';
const remoteEid = 30102; // Example target endpoint ID, Binance Smart Chain
const executorConfigType = 1; // 1 for executor
const ulnConfigType = 2; // 2 for UlnConfig

// Docs: https://docs.layerzero.network/v2/developers/evm/configuration/default-config#checking-default-configuration
async function getConfigAndDecode() {
    try {
        // Fetch and decode for sendLib (both Executor and ULN Config)
        const sendExecutorConfigBytes = await contract.getConfig(
            oappAddress,
            sendLibAddress,
            remoteEid,
            executorConfigType,
        );
        const executorConfigAbi = ['tuple(uint32 maxMessageSize, address executorAddress)'];
        const executorConfigArray = ethers.utils.defaultAbiCoder.decode(
            executorConfigAbi,
            sendExecutorConfigBytes,
        );
        console.log('Send Library Executor Config:', executorConfigArray);

        const sendUlnConfigBytes = await contract.getConfig(
            oappAddress,
            sendLibAddress,
            remoteEid,
            ulnConfigType,
        );
        const ulnConfigStructType = [
            'tuple(uint64 confirmations, uint8 requiredDVNCount, uint8 optionalDVNCount, uint8 optionalDVNThreshold, address[] requiredDVNs, address[] optionalDVNs)',
        ];
        const sendUlnConfigArray = ethers.utils.defaultAbiCoder.decode(
            ulnConfigStructType,
            sendUlnConfigBytes,
        );
        console.log('Send Library ULN Config:', sendUlnConfigArray);

        // Fetch and decode for receiveLib (only ULN Config)
        const receiveUlnConfigBytes = await contract.getConfig(
            oappAddress,
            receiveLibAddress,
            remoteEid,
            ulnConfigType,
        );
        const receiveUlnConfigArray = ethers.utils.defaultAbiCoder.decode(
            ulnConfigStructType,
            receiveUlnConfigBytes,
        );
        console.log('Receive Library ULN Config:', receiveUlnConfigArray);

    } catch (error) {
        console.error('Error fetching or decoding config:', error);
    }
}

// Execute the function
getConfigAndDecode();
