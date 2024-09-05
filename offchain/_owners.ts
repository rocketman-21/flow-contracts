import { createPublicClient, http, keccak256, type Address, encodeAbiParameters, toHex, fromRlp } from "viem";
import { getBeaconRootAndL2Timestamp } from "./src/getBeaconRootAndL2Timestamp";
import { base, mainnet } from "viem/chains";
import { getBeaconBlock } from "./src/getBeaconBlock";
import { getExecutionStateRootProof } from "./src/getExecutionStateRootProof";

// Create public clients for L2 (Base) and L1 (Ethereum mainnet)
const l2Client = createPublicClient({
  chain: base,
  transport: http()
})

const l1Client = createPublicClient({
  chain: mainnet,
  transport: http()
})

// Step 1: Get the latest beacon root and L2 timestamp
// This function retrieves the parentBeaconBlockRoot and timestamp from the latest L2 block
const beaconInfo = await getBeaconRootAndL2Timestamp(l2Client as any);

// Step 2: Fetch the beacon block using the beacon root
// This function makes an API call to retrieve the beacon block data
const block = await getBeaconBlock(beaconInfo.beaconRoot);

// Step 3: Generate the execution state root proof
// This function creates a proof for the execution state root within the beacon block
const stateRootInclusion = getExecutionStateRootProof(block);

// Example: Generating a storage proof for a specific token in a contract
const tokenId = BigInt(256);
const ownerMappingSlot = BigInt(3);
const slot = keccak256(encodeAbiParameters([{type: 'uint256'}, {type: 'uint256'}], [tokenId, ownerMappingSlot]))

// Step 4: Get the storage proof from the L1 client
const storageProof = await l1Client.getProof({
  address: '0x9c8ff314c9bc7f6e59a9d9225fb22946427edc03' as Address, // Nouns token contract address
  storageKeys: [slot],
  blockNumber: BigInt(block.body.executionPayload.blockNumber)
})

// Construct the final proof object
const proofObj = {
  beaconRoot: beaconInfo.beaconRoot,
  beaconOracleTimestamp: toHex(beaconInfo.timestampForL2BeaconOracle, {size: 32}),
  executionStateRoot: stateRootInclusion.leaf,
  stateRootProof: stateRootInclusion.proof,
  storageProof: storageProof.storageProof[0].proof,
  accountProof: storageProof.accountProof
}

// Verify that the execution state root matches
console.log('Execution Payload State Root:', toHex(block.body.executionPayload.stateRoot))
console.log('Proof Execution State Root:', proofObj.executionStateRoot)

// Write the proof object to a JSON file
await Bun.write(`outputs/_owners[${tokenId}].json`, JSON.stringify(proofObj));