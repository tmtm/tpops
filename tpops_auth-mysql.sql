# $Id: tpops_auth-mysql.sql,v 1.1 2002/12/03 16:26:34 tommy Exp $

create table user (
    uid int not null auto_increment,
    login char(16) not null,
    passwd char(16) not null,
    mail char(64) not null,
    maildir char(64) not null,
    quota int not null,
    primary key (uid),
    unique (login),
    unique (mail)
);

create table locks (
    uid int not null,
    pid int not null,
    host char(32) not null,
    timestamp timestamp not null,
    unique (uid),
    index (host)
);
