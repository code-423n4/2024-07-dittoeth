import { CodegenConfig } from "@graphql-codegen/cli";

const config: CodegenConfig = {
  schema: "http://localhost:8000/subgraphs/name/dittoeth/ditto-eth-subgraph",
  documents: ["frontend/**/*.tsx", "frontend/**/*.ts"],
  ignoreNoDocuments: true, // for better experience with the watcher
  generates: {
    "./frontend/lib/gql/": {
      preset: "client",
    },
  },
};

export default config;
