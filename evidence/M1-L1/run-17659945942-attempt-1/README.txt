Evidence bundle for C1/M1/L1
Repo:        MainMuck/Ci.cdcompany
Workflow:    C1-M1-L1 | build, sign, checksums, verify (warn)
Run ID:      17659945942
Run number:  13
Attempt:     1
Conclusion:  success
Commit SHA:  bbaa21cda10e46ef902f543d59d59b87f8929c6c

Contents:
- logs/*.zip                              -> логи по каждому job
- logs-17659945942.zip           -> общий ZIP всех логов run
- artifacts/c1-m1-l1-checks/*             -> IMAGE_DIGEST.txt, checksums.txt, *.sha256, sbom.cdx.json, predicate.json
- workflow/build-sign-verify.yml          -> снимок WF с комментариями
