// https://docs.chain.link/docs/historical-price-data/#roundid-in-proxy
export function computeRoundId(phaseId: number, aggregatorRoundId: number): string {
    const roundId = (BigInt(phaseId) << BigInt("64")) | BigInt(aggregatorRoundId)
    return roundId.toString()
}
