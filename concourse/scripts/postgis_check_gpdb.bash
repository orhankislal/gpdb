#!/bin/bash -l

set -eox pipefail

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${CWDIR}/common.bash"

function gen_env(){
  cat > /opt/run_test.sh <<-EOF
		trap look4results ERR

		function look4results() {

		    results_files="../gpMgmt/gpMgmt_testunit_results.log"

		    for results_file in \${results_files}; do
			if [ -f "\${results_file}" ]; then
			    cat <<-FEOF

						======================================================================
						RESULTS FILE: \${results_file}
						----------------------------------------------------------------------

						\$(cat "\${results_file}")

					FEOF
			fi
		    done
		    exit 1
		}
		base_path=\${1}
		source /usr/local/greenplum-db-devel/greenplum_path.sh
		source /opt/gcc_env.sh
		source \${base_path}/gpdb_src/gpAux/gpdemo/gpdemo-env.sh


		# cd \${base_path}/gpdb_src/gpMgmt/bin
		# make check
		# show results into concourse
		# cat \${base_path}/gpdb_src/gpMgmt/gpMgmt_testunit_results.log

	EOF

	chmod a+x /opt/run_test.sh
}

function setup_gpadmin_user() {
    ./gpdb_src/concourse/scripts/setup_gpadmin_user.bash "$TEST_OS"
}

function setup_postgis() {
 	cat > /opt/install_postgis.sh <<-EOF
		base_path=\${1}
		source /usr/local/greenplum-db-devel/greenplum_path.sh
		source /opt/gcc_env.sh
		cd /tmp/
		wget ftp://195.220.108.108/linux/centos/7.3.1611/os/x86_64/Packages/json-c-devel-0.11-4.el7_0.x86_64.rpm
		sudo yum install json-c-devel-0.11-4.el7_0.x86_64.rpm
		sudo yum install -y geos-devel
		sudo yum install -y proj-devel
		sudo yum install -y gdal-devel
		sudo yum install -y expat-devel
		sudo yum install -y patch
		sudo yum install -y CUnit CUnit-devel
		sudo yum install libxml2-devel -y
		wget ftp://invisible-island.net/byacc/byacc-20170430.tgz
		tar -xzf byacc-20170430.tgz
		cd byacc-20170430/
		./configure --enable-btyacc
		make
		sudo make install

		cd \${base_path}/postgis_src/postgis
		make remove
		make prepare
		cd build/postgis-2.1.5/
		./configure --with-pgconfig=$GPHOME/bin/pg_config --with-raster --without-topology --prefix=$GPHOME
		make
		sudo make install
		make check


		cd $GPHOME/share/postgresql/contrib/postgis-2.1
		psql template1 -f postgis.sql
		psql template1 -f postgis_comments.sql
		psql template1 -f spatial_ref_sys.sql
		psql template1 -f rtpostgis.sql
		psql template1 -f raster_comments.sql

	EOF

	chmod a+x /opt/install_postgis.sh
}

function _main() {

    configure
    install_gpdb
    setup_gpadmin_user
    make_cluster
    gen_env
    setup_postgis
    run_test
}

_main "$@"
