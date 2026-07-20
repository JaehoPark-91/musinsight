#!/bin/bash
################################################################################
#                                                                              #
#   Step 8: (DEPRECATED) CloudFront + Lambda@Edge Integration                  #
#                                                                              #
#   이 단계는 더 이상 필요하지 않습니다.                                          #
#   조직 SCP가 CloudFront 생성을 차단하여 아키텍처가 변경되었습니다:              #
#     CloudFront + Lambda@Edge  →  ALB HTTPS(ACM) + authenticate-cognito       #
#                                                                              #
#   This step is no longer needed. The org SCP blocks CloudFront creation,     #
#   so the architecture changed to ALB HTTPS (ACM) + authenticate-cognito.     #
#   Cognito auth is now attached to the ALB listener by 05-setup-cognito.sh.   #
#                                                                              #
################################################################################

YELLOW='\033[1;33m'; NC='\033[0m'
echo ""
echo -e "${YELLOW}Step 8은 더 이상 사용되지 않습니다 (ALB Cognito 인증으로 대체).${NC}"
echo -e "${YELLOW}Step 8 is deprecated — replaced by ALB Cognito auth (see Step 5).${NC}"
echo ""
exit 0
