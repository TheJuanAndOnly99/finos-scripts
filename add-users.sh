#!/bin/bash

# Organization name
ORG="finos-labs"

# List of teams and users
read -r -d '' TEAM_MEMBERS << EOM
learnaix-h-2025-akaza-team: anshuman-rai-27
learnaix-h-2025-bot-code-team: aditii010
learnaix-h-2025-hello-worlders-team: charvig23
learnaix-h-2025-shivam-dubey-team: Shivam-Dubey18
learnaix-h-2025-shoaib-akhtar-team: star-173
learnaix-h-2025-synapse-team: LeLuke007
learnaix-h-2025-nwaititans-team: saurabhanejad3
learnaix-h-2025-codehub-team: VKAUM
learnaix-h-2025-innouvetta-team: JatinAggarwal04
learnaix-h-2025-the-knights-templar-team: thesilentinvader042
learnaix-h-2025-project-genesis-team: kayyagamine
learnaix-h-2025-codebyte-team: Akanksha-Bathla
learnaix-h-2025-virtusa-team: MohammadYunis PasargiSangeetha priyankadiddi977-design mjayaweera
learnaix-h-2025-hackerlog-team: sarveshrastogi1 kunal-2004-ux
learnaix-h-2025-proctobots-team: pavanshanbhag04
learnaix-h-2025-ragdoll-team: AbhiPurohit1100 prarthana127 SOHAM2022 Krishang91
learnaix-h-2025-aib-team: alvinbengeorge SaanviKumar13 Abilaashss akarshghildyal itsdebanshuroy
learnaix-h-2025-lmntrx-team: Siddhartha-star chetankumar2004 akshayakunapareddy VarshikG0609 Sai-likith28
learnaix-h-2025-hackfusion-team: Harshita3942 theamitsiingh
learnaix-h-2025-unicoding-team: AnantSingla412
learnaix-h-2025-arion-team: SrinidhiL2004
learnaix-h-2025-ug26-team: Ujjyman gauravsahuuu Pratham2203
learnaix-h-2025-atomx-team: wolfiee1911 redducc
learnaix-h-2025-cucumber-town-team: thoma08 jkodoor89 arunjoji
learnaix-h-2025-incognito-team: abhinandanwadwa muskaannnr
learnaix-h-2025-solutionmakers-team: Dakshesh-007 bharath2468
learnaix-h-2025-crabs-team: muthu-py RahulJoshvaa Praveen-Nandan Makzz1
learnaix-h-2025-hackaholics-team: Ajay-kanna-356 Kishore-Babu-K AshokAdithya
learnaix-h-2025-error403-team: adnanxali
learnaix-h-2025-team-alpha-team: Kshitijkrojha
learnaix-h-2025-innovators-team: as2998 Paarth1809
learnaix-h-2025-devign-team: SAURABH-SINGH01 shreya2277 raj00003
learnaix-h-2025-tempname-team: g5277 Viviktha0709
learnaix-h-2025-vyakayan-team: HemJVK
learnaix-h-2025-cheque-mates-team: NileshSree1072
EOM

# Iterate over each line
while IFS= read -r line; do
    TEAM_NAME="${line%%:*}"
    USERS="${line#*:}"
    TEAM_SLUG="$(echo "$TEAM_NAME" | tr '[:upper:]' '[:lower:]')"

    echo "👥 Inviting users to team: $TEAM_NAME ($TEAM_SLUG)"

    # Clear failed_invites for this team
    > failed_invites.txt

    # Split users by space
    IFS=' ' read -ra USERNAMES <<< "$USERS"
    for username in "${USERNAMES[@]}"; do
        echo "➡️  Inviting $username to $TEAM_SLUG"
        if gh api --method PUT "/orgs/$ORG/teams/$TEAM_SLUG/memberships/$username" --silent > /dev/null; then
            echo "✅ Invited $username"
        else
            echo "⚠️ Failed to invite $username"
            echo "$username" >> failed_invites.txt
        fi
    done

    echo "✅ Finished inviting users to $TEAM_NAME"
    if [[ -s failed_invites.txt ]]; then
        echo "Failed to invite users:"
        cat failed_invites.txt
    fi
    echo

done <<< "$TEAM_MEMBERS"
