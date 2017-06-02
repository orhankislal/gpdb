#!/bin/bash -l

set -eox pipefail

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${CWDIR}/common.bash"


function setup_gpadmin_user() {
	./gpdb_src/concourse/scripts/setup_gpadmin_user.bash "$TEST_OS"
}

function prep_setup_postgis() {
	cat > /opt/setup_postgis.sh <<-EOF
		set -exo pipefail
		base_path=\${1}
		source /tmp/gpdb-deploy/greenplum_path.sh
		source /opt/gcc_env.sh
		source \${base_path}/gpdb_src/gpAux/gpdemo/gpdemo-env.sh
		# export MASTER_DATA_DIRECTORY=\${base_path}/gpdb_src/gpAux/gpdemo/datadirs/qddir/demoDataDir-1

		# cd /tmp/
		# wget ftp://195.220.108.108/linux/centos/7.3.1611/os/x86_64/Packages/json-c-devel-0.11-4.el7_0.x86_64.rpm
		# sudo yum install json-c-devel-0.11-4.el7_0.x86_64.rpm
		sudo yum install -y libxml2-devel
		sudo yum install -y geos-devel
		sudo yum install -y proj-devel
		sudo yum install -y gdal-devel
		sudo yum install -y expat-devel
		sudo yum install -y patch
		sudo yum install -y CUnit CUnit-devel
		wget ftp://invisible-island.net/byacc/byacc-20170430.tgz
		tar -xzf byacc-20170430.tgz
		cd byacc-20170430/
		./configure --enable-btyacc
		make
		sudo make install
		# export LD_LIBRARY_PATH=/usr/lib64:$LD_LIBRARY_PATH

		cd \${base_path}/postgis_src/postgis/
		# make remove
		# make prepare
		cd build/postgis-2.1.5/
		./configure --with-pgconfig=$GPHOME/bin/pg_config --with-raster --without-topology --prefix=$GPHOME --libdir=/usr/lib64
		make
		make install

		mv \${base_path}/postgis_src/postgis/build/postgis-2.1.5/regress/loader \${base_path}/postgis_src/postgis/build/postgis-2.1.5/regress/bkp_loader

		chown -R gpadmin:gpadmin \${base_path}/postgis_src
	EOF

	cat > /opt/install_postgis.sh <<-EOF
		set -exo pipefail
		base_path=\${1}
		source /tmp/gpdb-deploy/greenplum_path.sh
		source /opt/gcc_env.sh
		source \${base_path}/gpdb_src/gpAux/gpdemo/gpdemo-env.sh
		cd \${base_path}/postgis_src/postgis/build/postgis-2.1.5/

		make check

		gpstate -a

		cd $GPHOME/share/postgresql/contrib/postgis-2.1
		psql template1 -f postgis.sql > /dev/null
		psql template1 -f postgis_comments.sql > /dev/null
		psql template1 -f spatial_ref_sys.sql > /dev/null
		psql template1 -f rtpostgis.sql > /dev/null
		psql template1 -f raster_comments.sql > /dev/null

	EOF

	chmod a+x /opt/setup_postgis.sh
	chmod a+x /opt/install_postgis.sh
}


function prep_build_gppkg() {
	cat > /opt/build_gppkg.sh <<-EOF
		set -exo pipefail
		base_path=\${1}
		source /tmp/gpdb-deploy/greenplum_path.sh
		source /opt/gcc_env.sh

		cd \${base_path}/gpdb_src/gpAux
		make sync_tools [BLD_ARCH="rhel7_x86_64"]


		cd \${base_path}/postgis_src/postgis/package
		make \
			BLD_TARGETS="gppkg" \
			BLD_ARCH="rhel7_x86_64" \
			INSTLOC=$GPHOME \
			BLD_TOP="\${base_path}/gpdb_src/gpAux" \
			POSTGIS_DIR="\${base_path}/postgis_src/postgis/build/postgis-2.1.5" \
			gppkg

	EOF
	chmod a+x /opt/build_gppkg.sh
}


transfer_ownership_for_postgis() {
  chown -R gpadmin:gpadmin postgis_src
  [ -d /tmp/gpdb-deploy ] && chown -R gpadmin:gpadmin /tmp/gpdb-deploy
}

