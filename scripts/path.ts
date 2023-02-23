import * as fs from "fs"

const CONTRACT_DIT = "./contracts"

export interface ContractNameAndDir {
    name: string
    dir: string
}

export function getAllDeployedContractsNamesAndDirs(): ContractNameAndDir[] {
    const contracts: ContractNameAndDir[] = []
    fs.readdirSync(CONTRACT_DIT)
        .filter(file => file.includes(".sol"))
        .forEach(file => {
            contracts.push({ name: file, dir: CONTRACT_DIT })
        })
    return contracts
}
