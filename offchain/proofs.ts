import {
  createPublicClient,
  http,
  keccak256,
  type Address,
  encodeAbiParameters,
  toHex,
  fromRlp,
} from "viem";
import { getBeaconRootAndL2Timestamp } from "./src/getBeaconRootAndL2Timestamp";
import { base, mainnet } from "viem/chains";
import { getBeaconBlock } from "./src/getBeaconBlock";
import { getExecutionStateRootProof } from "./src/getExecutionStateRootProof";

// Create public clients for L2 (Base) and L1 (Ethereum mainnet)
const l2Client = createPublicClient({
  chain: base,
  transport: http(),
});

const l1Client = createPublicClient({
  chain: mainnet,
  transport: http(),
});

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
const ownerMappingSlot = BigInt(3);
const tokenIds = [BigInt(1016)];
const ownerProofs = await Promise.all(
  tokenIds.map(async (tokenId) => {
    const slot = keccak256(
      encodeAbiParameters(
        [{ type: "uint256" }, { type: "uint256" }],
        [tokenId, ownerMappingSlot],
      ),
    );

    // Step 4: Get the storage proof from the L1 client
    const proof = await l1Client.getProof({
      address: "0x9c8ff314c9bc7f6e59a9d9225fb22946427edc03" as Address, // Nouns token contract address
      storageKeys: [slot],
      blockNumber: BigInt(block.body.executionPayload.blockNumber),
    });

    return proof;
  }),
);

const delegateMappingSlot = BigInt(11);
const delegators: `0x${string}`[] = [
  "0x05A1ff0a32bc24265BCB39499d0c5D9A6cb2011c",
];
const delegateProofs = await Promise.all(
  delegators.map(async (delegator) => {
    const slot = keccak256(
      encodeAbiParameters(
        [{ type: "address" }, { type: "uint256" }],
        [delegator, delegateMappingSlot],
      ),
    );

    // Get the storage proof from the L1 client
    const proof = await l1Client.getProof({
      address: "0x9c8ff314c9bc7f6e59a9d9225fb22946427edc03" as Address, // Nouns token contract address
      storageKeys: [slot],
      blockNumber: BigInt(block.body.executionPayload.blockNumber),
    });

    return proof;
  }),
);

// Construct the final proof object
const ownerProofObj = {
  beaconRoot: beaconInfo.beaconRoot,
  beaconOracleTimestamp: toHex(beaconInfo.timestampForL2BeaconOracle, {
    size: 32,
  }),
  executionStateRoot: stateRootInclusion.leaf,
  stateRootProof: stateRootInclusion.proof,
  accountProof: ownerProofs[0].accountProof, // same for all
  ownershipStorageProof1: ownerProofs[0].storageProof[0].proof,
  delegateStorageProofs: delegateProofs.map(
    (proof) => proof.storageProof[0].proof,
  ),
};

// Verify that the execution state root matches
console.log(
  "Execution Payload State Root:",
  toHex(block.body.executionPayload.stateRoot),
);
console.log("Proof Execution State Root:", ownerProofObj.executionStateRoot);

// Write the proof object to a JSON file
await Bun.write(
  `outputs/proofs[${delegators}][${tokenIds}].json`,
  JSON.stringify(ownerProofObj),
);

// Construct a proof object without storage proofs
// const proofObjWithoutStorage = {
//   beaconRoot: beaconInfo.beaconRoot,
//   beaconOracleTimestamp: toHex(beaconInfo.timestampForL2BeaconOracle, {size: 32}),
//   executionStateRoot: stateRootInclusion.leaf,
//   stateRootProof: stateRootInclusion.proof,
//   accountProof: ownerProofs[0].accountProof, // same for all
// };

// // Verify that the execution state root matches for this object as well
// console.log('Proof Without Storage - Execution State Root:', proofObjWithoutStorage.executionStateRoot);

// // Write this new proof object to a separate JSON file
// await Bun.write(`outputs/proofWithoutStorage_${block.body.executionPayload.blockNumber}.json`, JSON.stringify(proofObjWithoutStorage));
