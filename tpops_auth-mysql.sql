# $Id: tpops_auth-mysql.sql,v 1.3 2004/07/15 13:33:51 tommy Exp $

create table user (
    uid int not null auto_increment,
    login char(16) not null,
    passwd char(40) not null,
    mail char(64) not null,
    maildir char(64) not null,
    quota int not null,
    primary key (uid),
    unique (login),
    unique (mail)
);
