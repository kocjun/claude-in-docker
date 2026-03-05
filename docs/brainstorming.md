클로드 코드의 --dangerously-skip-permissions 플래그를 안전하게 사용하는 방법
Docker, VM, Firejail 등 다양한 격리 실행 환경을 검토한 뒤 Vagrant 기반 가상머신(VM) 이 가장 적합하다고 판단
Vagrant를 통해 완전한 VM 격리, 재현 가능한 설정, 로컬 폴더 공유를 유지하면서도 Docker-in-Docker 문제를 피함
Claude Code가 VM 내에서 sudo 권한으로 자유롭게 시스템 조작을 수행하도록 설정, 실제로 웹앱 실행·DB 구성·테스트 자동화 등을 수행함
이 방식은 실수로 인한 파일시스템 손상 방지에 효과적이며, 필요 시 VM을 삭제·재생성해 안전하게 초기화 가능
배경
Claude Code를 사용할 때 매번 권한 요청을 확인해야 하는 불편함을 해소하기 위해 --dangerously-skip-permissions 플래그 사용을 시도함
이 플래그는 패키지 설치, 설정 변경, 파일 삭제 등 모든 작업을 사전 승인 없이 자동 수행
작업 흐름이 끊기지 않아 효율적이지만, 파일시스템 손상 위험이 존재함
이를 방지하기 위해 호스트 OS 계정과 분리된 환경에서 실행할 필요성을 인식함
고려한 방법들
Docker를 통한 격리를 우선 검토했으나, Claude가 Docker 이미지를 빌드하고 컨테이너를 실행해야 하므로 Docker-in-Docker 구성이 필요
이 경우 --privileged 모드가 요구되어 샌드박싱 목적이 무의미해짐
네트워크 중첩, 볼륨 마운트 권한 문제 등으로 복잡성과 불안정성이 증가함
기타 대안으로는 다음을 검토함
베어메탈 실행: Reddit 사례에서 데이터베이스나 홈 디렉터리 삭제 등 심각한 손상 사례 존재
sandbox-runtime: ACL 기반 접근 제어로, Claude가 코드 외에는 접근 불가하지만 완전한 자유도 부족
Firejail: Docker와 유사한 제약 존재
수동 VM 설정: 재현성 부족
클라우드 VM: 비용·지연·코드 업로드 필요성 문제
Vagrant 기반 접근
Vagrant를 이용해 완전한 VM 격리와 재현 가능한 설정을 확보
공유 폴더를 통해 로컬처럼 접근 가능
Docker-in-Docker 문제 없음, 필요 시 VM을 손쉽게 삭제·재생성 가능
VirtualBox 7.2.4 버전 사용 중 CPU 100% 점유 버그를 발견, GitHub 이슈를 통해 원인 확인
최종 Vagrantfile 구성은 다음과 같은 특징을 가짐
bento/ubuntu-24.04 베이스 이미지 사용
4GB 메모리, 2 CPU 할당
Docker, Node.js, npm, git, unzip 설치
@anthropic-ai/claude-code 전역 설치
vagrant 사용자를 Docker 그룹에 추가
실제 사용 방식
프로젝트 디렉터리에서 vagrant up → vagrant ssh → claude --dangerously-skip-permissions 순으로 실행
첫 부팅 시 프로비저닝에 몇 분 소요되며, 프로젝트별로 한 번만 Claude 로그인 필요
작업 종료 시 vagrant suspend로 VM 일시 중단 가능
Claude는 VM 내에서 sudo 권한을 부여받아 다음과 같은 작업 수행
웹앱 API 실행 및 curl로 점검
브라우저 설치 후 앱 수동 검사 및 E2E 테스트 생성
PostgreSQL DB 설정 및 마이그레이션 테스트
Docker 이미지 빌드 및 실행
이러한 환경 덕분에 Claude가 명령 실행·출력 확인·반복 과정을 스스로 처리 가능
성능 및 안전성
Linux + VirtualBox 환경에서 리소스 여유 충분, 파일 동기화 지연 없음
보호 가능한 항목
실수로 인한 파일시스템 손상
무분별한 패키지 설치 및 설정 변경
보호 불가능한 항목
프로젝트 폴더 삭제(양방향 동기화)
VM 탈출 취약점을 악용한 공격
네트워크 수준의 문제
데이터 유출(VM은 인터넷 접근 가능)
이 구성은 사고 방지용이며, 고급 공격 방어 목적은 아님
Git 기반 프로젝트라 손상 시에도 복구 용이, 필요 시 rsync 단방향 동기화로 더 엄격한 격리 가능
결론
VirtualBox CPU 버그 해결 후 마찰 없는 실행 환경 완성
Claude Code를 완전한 VM 샌드박스 내에서 자유롭게 실행 가능
문제가 발생하면 VM을 삭제 후 재생성하면 되며, Vagrantfile 하나로 재현성 확보
--dangerously-skip-permissions 플래그를 사용하는 경우, 이와 같은 격리 환경 구성이 강력히 권장됨
